import XCTest
@testable import DeskCore

final class IdeationReportParserTests: XCTestCase {
    private let report = """
    # Ideation — acme/app — 2026-09-12
    Flows: 4, from PROJECT_MAP.md       Kinds: perf | security

    ## CONFIRMED (2)                     ← eligible to file as `enhancement`
    - Course list re-sorts on every keystroke → sort once, on load
      gain: 180 ms per keystroke    cost: 2 h    doing nothing: the list stutters on long courses
      Sources/Courses/List.swift:88        touches: Sources/Courses/List.swift, Sources/Courses/Sort.swift
    - Tokens are read from disk per request → cache them
      gain: 40 ms per request    cost: 1 h    doing nothing: nothing measurable

    ## PLAUSIBLE (1)                     ← held, not filed
    - Image decode may block the first paint · could not be confirmed from the code alone

    ## REFUTED (1)
    - Batch the writes · moves the cost, does not remove it

    ## DECLINED BEFORE (1)
    - Rewrite the router · #41 · declined 2026-08-02

    ## ALREADY TRACKED (1)
    - Slow search · #42 · Sources/Search/Index.swift:120

    ## COST
    Declared 4 agents  ·  Actual 4 agents
    """

    func testEverySectionBecomesItsVerdictInOrder() {
        let found = IdeationReportParser.parse(report, runID: "2026-09-12")
        XCTAssertEqual(found.map(\.id), ["2026-09-12-C1", "2026-09-12-C2", "2026-09-12-P1", "2026-09-12-R1",
                                         "2026-09-12-D1", "2026-09-12-T1"])
        XCTAssertEqual(found.map(\.verdict), [.confirmed, .confirmed, .plausible, .refuted, .declined, .tracked])
    }

    func testAConfirmedBulletKeepsItsGainCostAndCostOfDoingNothing() {
        let first = IdeationReportParser.parse(report, runID: "r")[0]
        XCTAssertEqual(first.title, "Course list re-sorts on every keystroke")
        XCTAssertEqual(first.proposed, "sort once, on load")
        XCTAssertEqual(first.gain, "180 ms per keystroke")
        XCTAssertEqual(first.cost, "2 h")
        XCTAssertEqual(first.doingNothing, "the list stutters on long courses")
        XCTAssertEqual(first.locations, ["Sources/Courses/List.swift:88", "Sources/Courses/Sort.swift"])
    }

    func testNothingMeasurableIsKeptRatherThanDropped() {
        let second = IdeationReportParser.parse(report, runID: "r")[1]
        XCTAssertEqual(second.doingNothing, "nothing measurable")
        XCTAssertEqual(second.proposed, "cache them")
        XCTAssertEqual(second.gain, "40 ms per request")
    }

    func testAClaimWithNoArrowKeepsItsWholeTitleAndItsReason() {
        let plausible = IdeationReportParser.parse(report, runID: "r")[2]
        XCTAssertEqual(plausible.title, "Image decode may block the first paint")
        XCTAssertNil(plausible.proposed)
        XCTAssertEqual(plausible.summary, "could not be confirmed from the code alone")
        XCTAssertNil(plausible.gain)
    }

    func testTheHeaderSaysWhichKindsTheRunCovered() {
        XCTAssertEqual(IdeationReportParser.kinds(report), "perf | security")
        XCTAssertNil(IdeationReportParser.kinds("# Ideation\n\n## CONFIRMED (0)\n"))
    }

    func testAReportWithNoVerdictSectionsHasNoOpportunities() {
        XCTAssertEqual(IdeationReportParser.parse("# Ideation\n\n## COST\nDeclared 2 agents\n", runID: "x"), [])
    }

    func testAttackerMarkdownInABulletComesOutLiteral() {
        let hostile = "## CONFIRMED (1)\n- Looks fine → click [Open](file:///System/Applications/Calculator.app)\n  gain: run `rm -rf ~` to see\n"
        let opportunity = IdeationReportParser.parse(hostile, runID: "r")[0]
        XCTAssertFalse(opportunity.proposed?.contains("[Open](") ?? true, "a raw link would render as a one-click launch")
        XCTAssertEqual(opportunity.gain?.contains("\\`rm -rf \\~\\`"), true, "the code span must be escaped")
    }

    func testCountsAreReportedPerVerdictAndPerRun() {
        let found = IdeationReportParser.parse(report, runID: "2026-09-12")
        let ideation = IdeationReport(runs: [IdeationRun(id: "2026-09-12", label: "2026-09-12")], opportunities: found)
        XCTAssertEqual(ideation.count(of: .confirmed, run: "2026-09-12"), 2)
        XCTAssertEqual(ideation.count(of: .refuted, run: nil), 1)
        XCTAssertEqual(ideation.count(of: .confirmed, run: "other-run"), 0)
    }
}
