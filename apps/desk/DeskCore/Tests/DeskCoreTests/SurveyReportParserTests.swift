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
        XCTAssertTrue(finding.summary.contains("\\`rm -rf \\~\\`"), "the code span must be escaped")
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
}
