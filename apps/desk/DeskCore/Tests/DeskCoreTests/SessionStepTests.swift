import XCTest
@testable import DeskCore

final class SessionStepTests: XCTestCase {
    private let ids = ["a", "b", "c"]

    func testNextAndPreviousWrapAtBothEnds() {
        XCTAssertEqual(SessionStepRequest(1).target(from: "a", among: ids), "b")
        XCTAssertEqual(SessionStepRequest(1).target(from: "c", among: ids), "a")
        XCTAssertEqual(SessionStepRequest(-1).target(from: "a", among: ids), "c")
        XCTAssertEqual(SessionStepRequest(-1).target(from: "b", among: ids), "a")
    }

    /// From the starter, or from a session that has since left the list, forward is the first and back the last.
    func testFromNothingLandsOnAnEnd() {
        XCTAssertEqual(SessionStepRequest(1).target(from: nil, among: ids), "a")
        XCTAssertEqual(SessionStepRequest(-1).target(from: "gone", among: ids), "c")
        XCTAssertNil(SessionStepRequest(1).target(from: nil, among: []))
    }

    func testTwoPressesOfTheSameKeyAreTwoChanges() {
        XCTAssertNotEqual(SessionStepRequest(1), SessionStepRequest(1))
    }
}
