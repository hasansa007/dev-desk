import XCTest
@testable import DeskCore

final class RecentProjectsStoreTests: XCTestCase {
    private func makeStore(limit: Int = 10) -> RecentProjectsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return RecentProjectsStore(defaults: defaults, limit: limit)
    }

    func testRecordMovesProjectToFrontAndDeduplicates() {
        let store = makeStore()
        store.record(.local(path: "/a"), name: "A", displayPath: "~/a")
        store.record(.local(path: "/b"), name: "B", displayPath: "~/b")
        store.record(.local(path: "/a"), name: "A", displayPath: "~/a")
        XCTAssertEqual(store.entries.map(\.id), ["local:/a", "local:/b"])
    }

    func testLimitHolds() {
        let store = makeStore(limit: 2)
        store.record(.local(path: "/a"), name: "A", displayPath: "~/a")
        store.record(.local(path: "/b"), name: "B", displayPath: "~/b")
        store.record(.local(path: "/c"), name: "C", displayPath: "~/c")
        XCTAssertEqual(store.entries.map(\.id), ["local:/c", "local:/b"])
    }

    func testSamplesAreNotRecorded() {
        let store = makeStore()
        store.record(.sample(.studyHub), name: "StudyHub", displayPath: "~/code/studyhub")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveDeletesEntry() {
        let store = makeStore()
        store.record(.local(path: "/a"), name: "A", displayPath: "~/a")
        store.remove(.local(path: "/a"))
        XCTAssertTrue(store.entries.isEmpty)
    }
}
