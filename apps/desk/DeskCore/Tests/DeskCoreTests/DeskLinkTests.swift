import XCTest
@testable import DeskCore

final class DeskLinkTests: XCTestCase {
    func testRoundTripsTask() {
        let link = DeskLink.task("59")
        XCTAssertEqual(DeskLink(url: link.url), link)
    }

    func testRoundTripsFinding() {
        let link = DeskLink.finding("F-108")
        XCTAssertEqual(DeskLink(url: link.url), link)
    }

    func testRoundTripsPercentEncodedID() {
        let link = DeskLink.task("branch:feature/x")
        XCTAssertEqual(DeskLink(url: link.url), link)
    }

    func testRejectsNonDeskScheme() {
        XCTAssertNil(DeskLink(url: URL(string: "https://example.com/task/59")!))
    }

    func testRejectsEmptyID() {
        XCTAssertNil(DeskLink(url: URL(string: "desk://task/")!))
    }
}
