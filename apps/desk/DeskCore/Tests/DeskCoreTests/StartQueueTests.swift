import XCTest
@testable import DeskCore

final class StartQueueTests: XCTestCase {
    private func task(_ id: String, _ column: BoardColumn = .readyForDev, branch: String? = nil) -> DeskTask {
        DeskTask(id: id, issueNumber: Int(id), title: id, column: column, headerBadge: StatusBadge(.neutral, id), branchLine: "",
                 branch: branch, requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""), parallel: .none(""))
    }

    func testAReadyForDevCardQueuesOnlyWhenNoSlotIsFree() {
        XCTAssertTrue(StartQueue.queuesInsteadOfStarting(task("1"), freeSlots: 0))
        XCTAssertTrue(StartQueue.queuesInsteadOfStarting(task("1"), freeSlots: -1), "more running than the limit, as after lowering it")
        XCTAssertFalse(StartQueue.queuesInsteadOfStarting(task("1"), freeSlots: 1))
    }

    /// Pressing Start again on a card already in Queued must not start it past the limit — it stays parked.
    func testAQueuedCardStillQueuesWhileTheAppIsFull() {
        XCTAssertTrue(StartQueue.queuesInsteadOfStarting(task("1", .queued), freeSlots: 0))
        XCTAssertFalse(StartQueue.queuesInsteadOfStarting(task("1", .queued), freeSlots: 1), "a freed slot lets the same press run it")
    }

    /// A Continue on work already in progress is not a new slot, so it is never parked.
    func testAnInProgressCardIsNeverQueued() {
        for slots in [-1, 0, 1] {
            XCTAssertFalse(StartQueue.queuesInsteadOfStarting(task("1", .inProgress), freeSlots: slots), "\(slots) free")
        }
    }

    /// A branch means the work has begun (`isUnstarted` is false), whatever column the card sits in.
    func testACardWithABranchIsNeverQueued() {
        XCTAssertFalse(StartQueue.queuesInsteadOfStarting(task("1", .readyForDev, branch: "gh-1-x"), freeSlots: 0))
        XCTAssertFalse(StartQueue.queuesInsteadOfStarting(task("1", .queued, branch: "gh-1-x"), freeSlots: 0))
    }

    func testReleaseTakesQueuedCardsInBoardOrderUpToTheFreeSlots() {
        let board = [task("5", .backlog), task("9", .queued), task("3", .inProgress), task("2", .queued),
                     task("7", .review), task("4", .queued)]
        XCTAssertEqual(StartQueue.tasksToRelease(board: board, freeSlots: 6, runningTaskIDs: []), ["9", "2", "4"],
                       "queued cards only, board order not number order")
        XCTAssertEqual(StartQueue.tasksToRelease(board: board, freeSlots: 2, runningTaskIDs: []), ["9", "2"])
        XCTAssertEqual(StartQueue.tasksToRelease(board: board, freeSlots: 2, runningTaskIDs: ["9"]), ["2", "4"],
                       "a card already running keeps no place in line")
        XCTAssertEqual(StartQueue.tasksToRelease(board: board, freeSlots: 0, runningTaskIDs: []), [])
        XCTAssertEqual(StartQueue.tasksToRelease(board: board, freeSlots: -2, runningTaskIDs: []), [], "as after lowering the limit")
    }

    /// A released run is counted by the app only once its session is live, so a pass must subtract what it
    /// has already let go — otherwise the pass after a release spends the same slots twice.
    func testReleasesInFlightReduceTheSpendableSlots() {
        XCTAssertEqual(StartQueue.spendableSlots(appFree: 3, releasedNotYetLive: 0), 3, "nothing in flight leaves the app's count unchanged")
        XCTAssertEqual(StartQueue.spendableSlots(appFree: 3, releasedNotYetLive: 2), 1)
        XCTAssertEqual(StartQueue.spendableSlots(appFree: 3, releasedNotYetLive: 3), 0)
        XCTAssertEqual(StartQueue.spendableSlots(appFree: 2, releasedNotYetLive: 5), 0, "over-large in-flight count never goes negative")
        XCTAssertEqual(StartQueue.spendableSlots(appFree: 3, releasedNotYetLive: -1), 3, "a negative in-flight count frees nothing extra")
        XCTAssertEqual(StartQueue.spendableSlots(appFree: -1, releasedNotYetLive: 0), 0, "as after lowering the limit")
    }
}
