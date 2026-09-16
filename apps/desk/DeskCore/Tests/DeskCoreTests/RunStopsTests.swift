import XCTest
@testable import DeskCore

final class RunStopsTests: XCTestCase {
    func testDefaultsRunUnattended() {
        XCTAssertEqual(RunStops().arguments, ["--plan=decide", "--walkthrough=skip", "--file=skip", "--max-agents=40"])
    }

    /// A run has to plan: skipping the plan stop means deciding it.
    func testThePlanStopCannotBeSkipped() {
        XCTAssertEqual(RunStops(plan: .skip).plan, .decide)
    }

    func testStoredChoicesRoundTripAndBadValuesFallBack() {
        let stops = RunStops(plan: .alert, walkthrough: .decide, filing: .alert, maxAgents: 60)
        XCTAssertEqual(RunStops(stored: stops.stored, maxAgents: 60), stops)
        XCTAssertEqual(RunStops(stored: "nonsense", maxAgents: 1), RunStops(maxAgents: 5))
    }

    func testARefusalIsRecognisedOnAnyLine() {
        XCTAssertTrue(RunStops.isRefusal("Refused: the plan needs 63 agents and the limit is 40."))
        XCTAssertTrue(RunStops.isRefusal("Planning…\nRefused: the plan needs 63 agents"))
        XCTAssertFalse(RunStops.isRefusal("Report written to docs/findings/2026-09-16.md"))
    }
}
