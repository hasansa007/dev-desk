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
}
