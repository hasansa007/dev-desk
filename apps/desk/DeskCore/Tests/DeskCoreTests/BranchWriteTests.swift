import Foundation
import XCTest
@testable import DeskCore

final class BranchWriteTests: XCTestCase {
    func testSafeDeleteRefusesUnmergedWork() {
        XCTAssertEqual(BranchWrite.arguments(branch: "feat/x", force: false), ["branch", "-d", "--", "feat/x"])
    }

    func testForcedDeleteIsADifferentFlag() {
        XCTAssertEqual(BranchWrite.arguments(branch: "feat/x", force: true), ["branch", "-D", "--", "feat/x"])
    }

    func testABranchNamedLikeAnOptionIsStillJustAName() {
        // `--` ends the options, so git reads the next word as a ref however it is spelled.
        XCTAssertEqual(BranchWrite.arguments(branch: "--force", force: false), ["branch", "-d", "--", "--force"])
    }

    func testNamesGitWouldNotAcceptAreRefusedBeforeAnythingRuns() {
        XCTAssertNil(BranchWrite.arguments(branch: "  ", force: false))
        XCTAssertNil(BranchWrite.arguments(branch: "two words", force: false))
        XCTAssertNil(BranchWrite.arguments(branch: "refs/heads/x", force: false), "a full ref is not what -d takes")
    }

    func testTheNameIsTrimmedNotRejected() {
        XCTAssertEqual(BranchWrite.arguments(branch: "  feat/x \n", force: false), ["branch", "-d", "--", "feat/x"])
    }

    /// The gap this file did not cover: `arguments` was tested, the invocation was not, so the one git call in the
    /// app that skipped `GitCommand.read` skipped it silently. `branch -D` fires reference-transaction hooks.
    func testTheDeleteIsHardenedLikeEveryOtherGitCall() async throws {
        let runner = FakeRunner([FakeRunner.gitRead("branch -D -- feat/x"): .ok("")])
        try await BranchWrite(directory: URL(fileURLWithPath: "/repo"), runner: runner).delete(branch: "feat/x", force: true)
        let key = try XCTUnwrap(runner.keys.first)
        XCTAssertTrue(key.hasPrefix("git -c core.fsmonitor= -c core.hooksPath=/dev/null -c diff.external= "), key)
        XCTAssertTrue(key.contains("-c gpg.program=false"), key)
        XCTAssertEqual(runner.calls.first?.timeout, CommandTimeout.git, "a local branch delete is a git timeout, not gh's")
        XCTAssertEqual(runner.calls.first?.directory, URL(fileURLWithPath: "/repo"))
    }

    func testAFailedDeleteCarriesGitsOwnLastLine() async {
        let runner = FakeRunner([FakeRunner.gitRead("branch -d -- feat/x"): .failed(1, stderr: "error: the branch is not fully merged\n")])
        do {
            try await BranchWrite(directory: URL(fileURLWithPath: "/repo"), runner: runner).delete(branch: "feat/x", force: false)
            XCTFail("a non-zero git exit must throw")
        } catch {
            XCTAssertEqual((error as? BranchWriteError), .failed("error: the branch is not fully merged"))
        }
    }

    /// An uncounted branch is not a branch counted at zero. Reading nil as 0 is what let a card with no count
    /// offer a one-press delete under the sentence "nothing is lost".
    func testAnUncountedBranchStillAsksForItsName() {
        XCTAssertTrue(BranchWrite.requiresTypedName(unmerged: nil))
        XCTAssertTrue(BranchWrite.requiresTypedName(unmerged: 1))
        XCTAssertFalse(BranchWrite.requiresTypedName(unmerged: 0))
    }

    func testTheConfirmationCountsWhatWouldBeLost() {
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 1),
                       "Delete the branch feat/x and the 1 commit it holds that the base branch does not?")
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 6),
                       "Delete the branch feat/x and the 6 commits it holds that the base branch does not?")
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 0),
                       "Delete the branch feat/x? Its commits are already in the base branch.")
    }

    func testAnUncountedBranchSaysSoRatherThanClaimingNothingIsLost() {
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: nil),
                       "Delete the branch feat/x? Dev Desk has not counted what it holds that the base branch does not.")
    }
}

final class BranchAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheLabelShortensAsItAges() {
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-600), now: now), "10 min ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-7200), now: now), "2 h ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-8 * 86_400), now: now), "8 d ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-90 * 86_400), now: now), "3 mo ago")
    }
}

final class BoardOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ id: String, _ age: TimeInterval?) -> DeskTask {
        DeskTask(id: id, title: id, column: .inProgress, headerBadge: StatusBadge(.neutral, id), branchLine: "",
                 requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""),
                 parallel: .none(""), lastCommit: age.map { now.addingTimeInterval(-$0) })
    }

    func testDatedCardsComeNewestFirst() {
        let ordered = BoardOrder.newestFirst([task("old", 86_400), task("new", 60), task("mid", 3600)])
        XCTAssertEqual(ordered.map(\.id), ["new", "mid", "old"])
    }

    /// The bug the date-only sort had: `nil` became `.distantFuture`, so every undated card outranked real work.
    func testUndatedCardsSortAfterDatedOnes() {
        let ordered = BoardOrder.newestFirst([task("none", nil), task("dated", 3600)])
        XCTAssertEqual(ordered.map(\.id), ["dated", "none"])
    }

    /// A queue is all undated, so every pair compares equal — and Swift's sort is not documented as stable.
    /// Without the index tiebreak the ranking dev.py computed could be permuted by a library change alone.
    func testAnAllUndatedColumnKeepsTheOrderTheBoardBuiltIt() {
        let queue = (1...40).map { task("q\($0)", nil) }
        XCTAssertEqual(BoardOrder.newestFirst(queue).map(\.id), queue.map(\.id))
    }

    func testCardsCommittedAtTheSameInstantKeepTheirOrder() {
        let ordered = BoardOrder.newestFirst([task("first", 600), task("second", 600)])
        XCTAssertEqual(ordered.map(\.id), ["first", "second"])
    }
}
