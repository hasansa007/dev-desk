import XCTest
@testable import DeskCore

final class FindingsReportParserTests: XCTestCase {
    private let report = """
    # Findings — acme/app — 2026-09-10
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
        let findings = FindingsReportParser.parse(report, runID: "2026-09-10")
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

    /// Everything outside ARCHITECTURE is a defect, whichever verdict section it sits under. The kind is read
    /// from where the report put the bullet, and nowhere else says it.
    func testFindingsOutsideTheArchitectureSectionAreDefects() {
        let findings = FindingsReportParser.parse(report, runID: "2026-09-10")
        XCTAssertEqual(findings.map(\.kind), [.defect, .defect, .defect, .defect])
    }

    func testSummaryKeepsTheNonLocationPartsAndEveryFindingCarriesTheLimit() {
        let findings = FindingsReportParser.parse(report, runID: "2026-09-10")
        XCTAssertEqual(findings.map(\.summary), [
            "mechanism: the loop exits before appending · expected: every page is kept",
            "mechanism: the key was renamed",
            "why it could not be confirmed from the code: needs a device",
            "#42",
        ])
        XCTAssertTrue(findings.allSatisfy { $0.runID == "2026-09-10" })
        XCTAssertTrue(findings.allSatisfy { $0.limits == "A findings run checks code only; nothing here was reproduced in a running app." })
    }

    func testReportWithoutFindingSectionsHasNoFindings() {
        XCTAssertEqual(FindingsReportParser.parse("# Findings\n\n## ARCHITECTURE\n- drift → move\n", runID: "x"), [])
    }

    func testAttackerMarkdownInABulletComesOutLiteral() {
        let report = "## PLAUSIBLE (1)\n- Looks fine · click [Open](file:///System/Applications/Calculator.app) or run `rm -rf ~` to see\n"
        let finding = FindingsReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.title, "Looks fine")
        XCTAssertTrue(finding.summary.hasPrefix("click \\[Open\\]"), "the link brackets must be escaped")
        XCTAssertFalse(finding.summary.contains("[Open]("), "a raw link would render as a one-click launch")
        XCTAssertTrue(finding.summary.contains("run rm -rf \\~ to see"), "code markers come off, the text stays")
        XCTAssertFalse(finding.summary.contains("`"), "a code span is not rendered, so its markers are noise")
    }

    func testFrameworkRoutePathsCountAsLocations() {
        let report = "## CONFIRMED (1)\n- Route params lost · app/[id]/page.tsx:12 · app/(auth)/login/page.tsx:7 · src/routes/+page.svelte:3 · mechanism: step 1 drops the id\n"
        let finding = FindingsReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.locations, ["app/[id]/page.tsx:12", "app/(auth)/login/page.tsx:7", "src/routes/+page.svelte:3"])
        XCTAssertEqual(finding.summary, "mechanism: step 1 drops the id")
    }

    /// The row menu and the detail pane both file; they have to hand the door the same thing.
    func testBacklogDescriptionCarriesTheClaimItsEvidenceAndItsRun() {
        let report = "## CONFIRMED (1)\n- Token never refreshes · src/auth.ts:31 · mechanism: the timer is cleared on blur\n"
        let finding = FindingsReportParser.parse(report, runID: "run-0940")[0]
        let description = finding.backlogDescription
        XCTAssertTrue(description.hasPrefix("Token never refreshes. "), description)
        XCTAssertTrue(description.contains("Sources: src/auth.ts:31."), description)
        XCTAssertTrue(description.contains("run run-0940"), description)
        XCTAssertTrue(description.contains(finding.verificationLabel), description)
    }

    func testBacklogDescriptionOmitsSourcesWhenThereAreNone() {
        let finding = FindingsReportParser.parse("## PLAUSIBLE (1)\n- Slow start\n", runID: "r")[0]
        XCTAssertFalse(finding.backlogDescription.contains("Sources:"))
    }

    /// The shape dev:findings actually writes: a claim on the bullet, everything else indented beneath it.
    func testABulletsIndentedLinesAreItsBody() {
        let report = """
        ## CONFIRMED (1)

        - **Combine publisher emits 0 reminders** · `Services/ReminderService.swift:54-66`
          · mechanism: `promise(.success(reminders))` at :63 fires synchronously after merely scheduling the
          three fetches. · expected: compose three publishers (Zip/MergeMany + collect).
          touches: `Services/ReminderService.swift`   blocks: shares the file with two other findings

        """
        let finding = FindingsReportParser.parse(report, runID: "2026-08-31")[0]
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
        let findings = FindingsReportParser.parse(report, runID: "2026-09-13")
        XCTAssertEqual(findings.map(\.id), ["2026-09-13-C1", "2026-09-13-C2"])
        XCTAssertEqual(findings.map(\.title), ["Tapping \"Don't Allow\" shows \"Something Went Wrong\"",
                                               "The whole contacts fetch runs on the main thread"])
        XCTAssertEqual(findings[0].locations, ["ContactsStore.swift:103", "ContactsStore.swift"])
        XCTAssertTrue(findings[0].summary.contains("mechanism"), findings[0].summary)
        XCTAssertFalse(findings[0].summary.contains("conflicts:"), "structured fields are not prose")
    }

    /// ARCHITECTURE carries its own verdicts under bold lines. Its drift lists are findings with a move
    /// attached; its prose and its "missed by the finder" note are not.
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

        **Missed by the finder, found by both checkers**
        - `MockGenerator` has no callers. Already CONFIRMED as #12.
        """
        let findings = FindingsReportParser.parse(report, runID: "r")
        XCTAssertEqual(findings.map(\.id), ["r-C1", "r-C2", "r-P1"])
        XCTAssertEqual(findings.map(\.categories), [[.new], [.new], [.needsDecision]])
        XCTAssertEqual(findings.map(\.kind), [.architecture, .architecture, .architecture],
                       "a drift is not a defect: the section it was read under is what says so")
        XCTAssertTrue(findings[0].title.hasPrefix("arch-1:"), findings[0].title)
        XCTAssertEqual(findings[0].locations, ["ContactDetailView.swift:104-115"])
        XCTAssertFalse(findings.contains { $0.title.contains("MockGenerator") },
                       "a note about what the finder missed is not itself a finding")
        XCTAssertFalse(findings.contains { $0.title.contains("Actual") || $0.title.contains("Recommend") },
                       "the section's own prose bullets are not findings")
    }

    /// One report holds both halves, and the heading that ends ARCHITECTURE ends its kind with it: what comes
    /// after is a defect again, not a drift inherited from the section above.
    func testTheKindGoesBackToDefectWhenTheArchitectureSectionEnds() {
        let report = """
        ## ARCHITECTURE

        **Drift — CONFIRMED (both checkers)**
        - arch-1: dead copy at `View.swift:104-115` → delete it.

        ## CONFIRMED (1)

        - Sync drops the last page · `Pager.swift:88` · mechanism: the loop exits before appending
        """
        let findings = FindingsReportParser.parse(report, runID: "r")
        XCTAssertEqual(findings.map { $0.title.hasPrefix("arch-1:") }, [true, false])
        XCTAssertEqual(findings.map(\.kind), [.architecture, .defect])
    }

    /// A location on the continuation line is still where the finding is, and used to be lost entirely.
    func testLocationBelowTheClaimIsStillALocation() {
        let report = """
        ## CONFIRMED (1)

        - **Async fetch returns 0 reminders**
          · `Services/ReminderService.swift:68-79` · mechanism: three unstructured tasks are fire-and-forget.

        """
        let finding = FindingsReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(finding.locations, ["Services/ReminderService.swift:68-79"])
        XCTAssertEqual(finding.title, "Async fetch returns 0 reminders")
    }

    // MARK: - What the run filed (the report's FILED table and ALREADY TRACKED merges)

    private let filedReport = """
    ## CONFIRMED (3)

    1. **Key alias deletes another owner's course** · `web/app/lib/safe-key.js:42`
       id: C1   type: Data flow   group: none
    2. **A missing PDF freezes the server** · `web/app/lib/coursePdf.js:55`
       id: C2   type: Logic   group: none
    3. **Append spends a whole grant** · `web/app/lib/append-handler.js:247`
       id: C10   type: UI   group: none

    ## ARCHITECTURE

    **Drift — CONFIRMED**
    - A1 — regenerate checks entitlement before ownership · `regenerate/route.js:67`
      id: A1   type: Architecture   group: none

    ## ALREADY TRACKED (3)

    A1 → #784 · merged (same fix, second route)
    C3 → #790 · related · C4 → #777 · related

    ## FILED

    | id | issue | finding | milestone |
    |----|-------|---------|-----------|
    | C1 | #810 | key alias | Access |
    | C2 | #811 | pdf freeze | unplaced |
    """

    func testTheFiledTableMarksEachFindingWithItsIssue() {
        let byRef = Dictionary(uniqueKeysWithValues: FindingsReportParser.parse(filedReport, runID: "r")
            .compactMap { f in f.coordination.ref.map { ($0, f) } })
        XCTAssertEqual(byRef["C1"]?.filing, .filed(810))
        XCTAssertEqual(byRef["C2"]?.filing, .filed(811))
    }

    func testAMergeLineMarksTheFindingAsAddedToTheOpenIssue() {
        let a1 = FindingsReportParser.parse(filedReport, runID: "r").first { $0.coordination.ref == "A1" }
        XCTAssertEqual(a1?.filing, .merged(784))
        XCTAssertEqual(a1?.filing?.label, "Added to #784")
    }

    func testRelatedIsNotFiledAndAHeldFindingStaysOpen() {
        let filings = FindingsReportParser.filings(filedReport)
        XCTAssertNil(filings["C3"], "related means a new issue was still needed")
        XCTAssertNil(filings["C4"])
        let c10 = FindingsReportParser.parse(filedReport, runID: "r").first { $0.coordination.ref == "C10" }
        XCTAssertNil(c10?.filing, "held by the cap: not in FILED, so it still waits on a decision")
    }

    func testTheTableHeaderAndRuleAreNotRows() {
        let filings = FindingsReportParser.filings(filedReport)
        XCTAssertEqual(Set(filings.keys), ["C1", "C2", "A1"])
    }

    func testADriftTitleIsItsFirstLineNotItsDetail() {
        let report = """
        ## ARCHITECTURE

        **Drift — CONFIRMED**
        - A2 — The merge route reads course content from disk
          detail: exactly one route does, `merge/route.js:31`, and returns 409 on hosted courses.
          id: A2   type: Architecture   group: none
        """
        let a2 = FindingsReportParser.parse(report, runID: "r").first
        XCTAssertEqual(a2?.title, "A2 — The merge route reads course content from disk")
        XCTAssertTrue(a2?.summary.contains("exactly one route does") ?? false, "the detail stays in the body")
    }

    func testAReportWithNoFiledSectionFilesNothing() {
        XCTAssertTrue(FindingsReportParser.filings("## CONFIRMED (0)\n").isEmpty)
    }
}
