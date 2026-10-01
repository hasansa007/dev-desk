import XCTest
@testable import DeskCore

final class AutoSchedulerTests: XCTestCase {
    private static let base = "refs/remotes/origin/main"
    private static let fork = "This pull request comes from a fork, so its branch isn't in this repository. The shell opens at the project root."

    /// A task numbered for its id, unless the id isn't a number.
    private func task(_ id: String, _ column: BoardColumn = .readyForDev, branch: String? = nil, noBranchNote: String? = nil,
                      baseRef: String? = AutoSchedulerTests.base) -> DeskTask {
        DeskTask(id: id, issueNumber: Int(id), title: id, column: column, headerBadge: StatusBadge(.neutral, id), branchLine: "",
                 branch: branch, noBranchNote: noBranchNote, baseRef: baseRef,
                 requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""), parallel: .none(""))
    }

    private func pick(_ board: [DeskTask], running: Set<String> = [], started: Set<String> = [], waiting: Set<String> = [],
                      across: Int = 0, limit: Int = 3) -> [String] {
        AutoScheduler.tasksToStart(board: board, runningAgentTaskIDs: running, alreadyStarted: started, waiting: waiting,
                                   runningAgentsAcrossApp: across, limit: limit)
    }

    /// Ready for dev is where planned work sits now (ADR 0035); Queued is the wait for a free slot, and
    /// the wiring that starts from it arrives separately — so Auto must not pick a queued card yet.
    func testOnlyReadyForDevTasksArePickedInBoardOrder() {
        let board = [task("5", .backlog), task("9"), task("3", .inProgress), task("2"), task("6", .queued),
                     task("7", .review), task("8", .done), task("4")]
        XCTAssertEqual(pick(board, limit: 6), ["9", "2", "4"], "board order, not number order")
    }

    func testTasksWithoutANumberWithAForkNoteWithAnAgentRunningOrAlreadyStartedAreSkipped() {
        let board = [task("pr:60"), task("51", noBranchNote: Self.fork), task("10"), task("11"), task("12"), task("13")]
        XCTAssertEqual(pick(board, running: ["10"], started: ["11"], across: 1, limit: 6), ["12", "13"])
    }

    func testATaskWithNoBranchAndNoBaseRefIsNeverStarted() {
        // Its agent would open at the project root (rule 4), which Auto never does.
        let board = [task("20", baseRef: nil), task("21", branch: "gh-21-x", baseRef: nil), task("22")]
        XCTAssertEqual(pick(board), ["21", "22"], "a task with a branch needs no base ref")
    }

    func testItStartsOnlyWhatTheLimitLeavesAcrossTheApp() {
        let board = (1...8).map { task(String($0)) }
        XCTAssertEqual(pick(board, across: 0, limit: 3), ["1", "2", "3"])
        XCTAssertEqual(pick(board, across: 2, limit: 3), ["1"], "agents in other windows count")
        XCTAssertEqual(pick(board, across: 3, limit: 3), [])
        XCTAssertEqual(pick(board, across: 5, limit: 3), [], "more running than the limit, as after lowering it, starts none")
        XCTAssertEqual(pick(board, across: -2, limit: 3), ["1", "2", "3"], "never more than the limit")
        XCTAssertEqual(pick(Array(board.prefix(2)), limit: 3), ["1", "2"])
    }

    func testTheLimitIsClampedToOneThroughTen() {
        let board = (1...12).map { task(String($0)) }
        XCTAssertEqual(pick(board, limit: 0), ["1"])
        XCTAssertEqual(pick(board, limit: -4), ["1"])
        XCTAssertEqual(pick(board, limit: 15), (1...10).map(String.init))
        XCTAssertEqual(pick(board, across: 9, limit: 15), ["1"], "the clamped limit, not the one asked for, leaves the slots")
    }

    /// A card whose blocker is open is passed over without spending a slot, so the cards that do not depend on it run beside each other.
    func testAWaitingCardIsPassedOverAndItsSlotGoesToTheNextIndependentOne() {
        let board = (1...5).map { task(String($0)) }
        XCTAssertEqual(pick(board, waiting: ["1", "3"], limit: 3), ["2", "4", "5"])
        XCTAssertEqual(pick(board, waiting: ["1", "2", "3", "4", "5"], limit: 3), [], "everything waiting starts nothing")
        XCTAssertEqual(pick(board, waiting: ["3"], limit: 3), ["1", "2", "4"])
    }
}
