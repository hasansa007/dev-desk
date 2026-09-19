import XCTest
@testable import DeskCore

/// ADR 0046 decision 11: Start checks for code a running task is changing.
final class StartOverlapTests: XCTestCase {
    private func task(_ n: Int, _ column: BoardColumn, touches: [CodeTouch] = [], changed: [String] = []) -> DeskTask {
        let changes: Surface<ChangeSet> = changed.isEmpty ? .unavailable("")
            : .available(ChangeSet(files: changed.map { ChangedFile(id: $0, displayPath: $0, additions: 1, deletions: 0) }, baseNote: ""))
        var t = DeskTask(id: String(n), issueNumber: n, title: "t\(n)", column: column, headerBadge: StatusBadge(.neutral, ""),
                         branchLine: "", requirements: .unavailable(""), changes: changes, evidence: .unavailable(""), parallel: .none(""))
        t.touches = touches
        return t
    }

    func testTouchesAreReadFromTheScopeLineWithNotesStripped() {
        let body = "## Scope\n- touches: `web/app/lib/tts-handler.js › ttsSynthesize()` (gate by default); `web/app/api/tts/route.js › POST()`\n- related: #790"
        XCTAssertEqual(StartOverlaps.touches(inBody: body), [
            CodeTouch(file: "web/app/lib/tts-handler.js", code: "ttsSynthesize"),
            CodeTouch(file: "web/app/api/tts/route.js", code: "POST"),
        ])
    }

    func testTheSameFunctionInARunningTaskAsks() {
        let mine = task(816, .readyForDev, touches: [CodeTouch(file: "web/app/api/course/[key]/regenerate/route.js", code: "POST")])
        let running = task(814, .inProgress, touches: [CodeTouch(file: "regenerate/route.js", code: "POST")])
        let found = StartOverlaps.find(mine, among: [mine, running])
        XCTAssertEqual(found.map(\.issue), [814])
        XCTAssertTrue(found[0].isSameCode)
    }

    func testTheSameFileWithDifferentFunctionsOrOnlyBranchChangesIsANote() {
        let mine = task(1, .readyForDev, touches: [CodeTouch(file: "a/route.js", code: "GET")])
        let other = task(2, .inProgress, touches: [CodeTouch(file: "a/route.js", code: "POST")])
        let branchOnly = task(3, .inProgress, changed: ["a/route.js"])
        let found = StartOverlaps.find(mine, among: [other, branchOnly])
        XCTAssertEqual(found.map(\.issue), [2, 3])
        XCTAssertFalse(found.contains(where: \.isSameCode))
    }

    func testTasksNotInProgressAndATaskWithNoTouchesMeetNothing() {
        let mine = task(1, .readyForDev, touches: [CodeTouch(file: "x.js", code: "f")])
        XCTAssertTrue(StartOverlaps.find(mine, among: [task(2, .readyForDev, touches: [CodeTouch(file: "x.js", code: "f")])]).isEmpty)
        XCTAssertTrue(StartOverlaps.find(task(3, .readyForDev), among: [task(4, .inProgress, changed: ["x.js"])]).isEmpty)
    }

    func testAQueuedWaitAddsOnceAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("waits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        LocalWaits().adding(814, to: 816).adding(814, to: 816).write(projectRoot: root)
        XCTAssertEqual(LocalWaits.read(projectRoot: root).waits, ["816": [814]])
    }
}
