import XCTest
@testable import DeskCore

final class SurveyReportParserTests: XCTestCase {
    private let report = """
    # Survey — acme/app — 2026-09-10
    Flows: 3, from PROJECT_MAP.md       Scope: all

    ## CONFIRMED (2)          ← eligible to file
    - Sync drops the last page · Sources/Sync/Pager.swift:88 · mechanism: the loop exits before appending · expected: every page is kept
      touches: Sources/Sync/Pager.swift, Sources/Sync/Store.swift        blocks: none
    - Settings reset on upgrade · `Sources/Settings/Migrate.swift:14` · mechanism: the key was renamed

    ## PLAUSIBLE (1)          ← held, not filed
    - Crash when offline · why it could not be confirmed from the code: needs a device

    ## ARCHITECTURE
    Actual: 3 MVVM, 1 MVC   Recommend: MVVM   Cost of doing nothing: drift
    - Legacy controller → move to a view model

    ## ALREADY TRACKED (1)
    - Slow search · #42 · Sources/Search/Index.swift:120

    ## COST
    Declared 3 agents  ·  Actual 3 agents
    """

    func testEachSectionBecomesItsCategoryWithLocations() {
        let findings = SurveyReportParser.parse(report, runID: "2026-09-10")
        XCTAssertEqual(findings.map(\.id), ["2026-09-10-C1", "2026-09-10-C2", "2026-09-10-P1", "2026-09-10-T1"])
        XCTAssertEqual(findings.map(\.categories), [[.new], [.new], [.needsDecision], [.knownNewEvidence]])
        XCTAssertEqual(findings.map(\.listDetail), ["New", "New", "Needs a decision", "Known · new evidence"])
        XCTAssertEqual(findings.map(\.verificationLabel), ["Code-inspected · confirmed by review", "Code-inspected · confirmed by review",
                                                           "Unconfirmed observation", "Already tracked"])
        XCTAssertEqual(findings.map(\.title), ["Sync drops the last page", "Settings reset on upgrade", "Crash when offline", "Slow search"])
        XCTAssertEqual(findings.map(\.locations), [
            ["Sources/Sync/Pager.swift:88", "Sources/Sync/Pager.swift", "Sources/Sync/Store.swift"],
            ["Sources/Settings/Migrate.swift:14"],
            [],
            ["Sources/Search/Index.swift:120"],
        ])
    }

    func testSummaryKeepsTheNonLocationPartsAndEveryFindingCarriesTheLimit() {
        let findings = SurveyReportParser.parse(report, runID: "2026-09-10")
        XCTAssertEqual(findings.map(\.summary), [
            "mechanism: the loop exits before appending · expected: every page is kept",
            "mechanism: the key was renamed",
            "why it could not be confirmed from the code: needs a device",
            "#42",
        ])
        XCTAssertTrue(findings.allSatisfy { $0.runID == "2026-09-10" })
        XCTAssertTrue(findings.allSatisfy { $0.limits == "Survey checks code only; nothing here was reproduced in a running app." })
    }

    func testReportWithoutFindingSectionsHasNoFindings() {
        XCTAssertEqual(SurveyReportParser.parse("# Survey\n\n## ARCHITECTURE\n- drift → move\n", runID: "x"), [])
    }

    func testAttackerMarkdownInABulletComesOutLiteral() {
        let report = "## PLAUSIBLE (1)\n- Looks fine · click [Open](file:///System/Applications/Calculator.app) or run `rm -rf ~` to see\n"
        let finding = SurveyReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.title, "Looks fine")
        XCTAssertTrue(finding.summary.hasPrefix("click \\[Open\\]"), "the link brackets must be escaped")
        XCTAssertFalse(finding.summary.contains("[Open]("), "a raw link would render as a one-click launch")
        XCTAssertTrue(finding.summary.contains("run rm -rf \\~ to see"), "code markers come off, the text stays")
        XCTAssertFalse(finding.summary.contains("`"), "a code span is not rendered, so its markers are noise")
    }

    func testFrameworkRoutePathsCountAsLocations() {
        let report = "## CONFIRMED (1)\n- Route params lost · app/[id]/page.tsx:12 · app/(auth)/login/page.tsx:7 · src/routes/+page.svelte:3 · mechanism: step 1 drops the id\n"
        let finding = SurveyReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.locations, ["app/[id]/page.tsx:12", "app/(auth)/login/page.tsx:7", "src/routes/+page.svelte:3"])
        XCTAssertEqual(finding.summary, "mechanism: step 1 drops the id")
    }

    /// The row menu and the detail pane both file; they have to hand the door the same thing.
    func testBacklogDescriptionCarriesTheClaimItsEvidenceAndItsRun() {
        let report = "## CONFIRMED (1)\n- Token never refreshes · src/auth.ts:31 · mechanism: the timer is cleared on blur\n"
        let finding = SurveyReportParser.parse(report, runID: "run-0940")[0]
        let description = finding.backlogDescription
        XCTAssertTrue(description.hasPrefix("Token never refreshes. "), description)
        XCTAssertTrue(description.contains("Sources: src/auth.ts:31."), description)
        XCTAssertTrue(description.contains("run run-0940"), description)
        XCTAssertTrue(description.contains(finding.verificationLabel), description)
    }

    func testBacklogDescriptionOmitsSourcesWhenThereAreNone() {
        let finding = SurveyReportParser.parse("## PLAUSIBLE (1)\n- Slow start\n", runID: "r")[0]
        XCTAssertFalse(finding.backlogDescription.contains("Sources:"))
    }

    /// The shape dev:survey actually writes: a claim on the bullet, everything else indented beneath it.
    func testABulletsIndentedLinesAreItsBody() {
        let report = """
        ## CONFIRMED (1)

        - **Combine publisher emits 0 reminders** · `Services/ReminderService.swift:54-66`
          · mechanism: `promise(.success(reminders))` at :63 fires synchronously after merely scheduling the
          three fetches. · expected: compose three publishers (Zip/MergeMany + collect).
          touches: `Services/ReminderService.swift`   blocks: shares the file with two other findings

        """
        let finding = SurveyReportParser.parse(report, runID: "2026-08-31")[0]
        XCTAssertEqual(finding.title, "Combine publisher emits 0 reminders")
        XCTAssertTrue(finding.summary.contains("mechanism"), finding.summary)
        XCTAssertTrue(finding.summary.contains("fires synchronously after merely scheduling the three fetches"),
                      "a wrapped line continues the sentence: \(finding.summary)")
        XCTAssertTrue(finding.summary.contains("expected"), finding.summary)
        XCTAssertFalse(finding.summary.contains("touches:"), "structured fields are not prose")
        XCTAssertFalse(finding.summary.contains("blocks:"), "structured fields are not prose")
        XCTAssertEqual(finding.locations, ["Services/ReminderService.swift:54-66", "Services/ReminderService.swift"])
    }

    /// A real run ranked CONFIRMED by cost and wrote it numbered. Reading only dashes showed the seven held
    /// PLAUSIBLE items and dropped twelve confirmed defects — the worst seventh of the report, alone on screen.
    func testANumberedFindingIsAFinding() {
        let report = """
        ## CONFIRMED (2)          ← eligible to file (ranked by cost-if-it-bites)

        1. **Tapping "Don't Allow" shows "Something Went Wrong"**
           · `ContactsStore.swift:103`
           · mechanism: the request throws on denial, so the guard never runs.
           touches: ContactsStore.swift        conflicts: #2, #11 (same file)

        2. **The whole contacts fetch runs on the main thread**
           · `ContactsStore.swift:68` · mechanism: the store is MainActor-isolated.

        """
        let findings = SurveyReportParser.parse(report, runID: "2026-09-13")
        XCTAssertEqual(findings.map(\.id), ["2026-09-13-C1", "2026-09-13-C2"])
        XCTAssertEqual(findings.map(\.title), ["Tapping \"Don't Allow\" shows \"Something Went Wrong\"",
                                               "The whole contacts fetch runs on the main thread"])
        XCTAssertEqual(findings[0].locations, ["ContactsStore.swift:103", "ContactsStore.swift"])
        XCTAssertTrue(findings[0].summary.contains("mechanism"), findings[0].summary)
        XCTAssertFalse(findings[0].summary.contains("conflicts:"), "structured fields are not prose")
    }

    /// ARCHITECTURE carries its own verdicts under bold lines. Its drift lists are findings with a move
    /// attached; its prose and its "missed by the surveyor" note are not.
    func testTheArchitectureSectionsDriftListsAreFindings() {
        let report = """
        ## ARCHITECTURE

        Two checkers recounted from the files independently. Every count matches.

        - **Actual:** 2 screens, 7 call sites
        - **Recommend:** all access lives in the store

        **Drift — CONFIRMED (both checkers)**
        - arch-1: dead `requestAccessIfNeeded` copy at `ContactDetailView.swift:104-115` → delete it.
        - arch-3: `FavoritesManager` in a view file → move it to its own file.

        **Drift — PLAUSIBLE (held)**
        - arch-4: delete the CHANGELOG block at `ContactsStore.swift:15-19`.

        **Missed by the surveyor, found by both checkers**
        - `MockGenerator` has no callers. Already CONFIRMED as #12.
        """
        let findings = SurveyReportParser.parse(report, runID: "r")
        XCTAssertEqual(findings.map(\.id), ["r-C1", "r-C2", "r-P1"])
        XCTAssertEqual(findings.map(\.categories), [[.new], [.new], [.needsDecision]])
        XCTAssertTrue(findings[0].title.hasPrefix("arch-1:"), findings[0].title)
        XCTAssertEqual(findings[0].locations, ["ContactDetailView.swift:104-115"])
        XCTAssertFalse(findings.contains { $0.title.contains("MockGenerator") },
                       "a note about what the surveyor missed is not itself a finding")
        XCTAssertFalse(findings.contains { $0.title.contains("Actual") || $0.title.contains("Recommend") },
                       "the section's own prose bullets are not findings")
    }

    /// A location on the continuation line is still where the finding is, and used to be lost entirely.
    func testLocationBelowTheClaimIsStillALocation() {
        let report = """
        ## CONFIRMED (1)

        - **Async fetch returns 0 reminders**
          · `Services/ReminderService.swift:68-79` · mechanism: three unstructured tasks are fire-and-forget.

        """
        let finding = SurveyReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.locations, ["Services/ReminderService.swift:68-79"])
        XCTAssertEqual(finding.title, "Async fetch returns 0 reminders")
    }
}
