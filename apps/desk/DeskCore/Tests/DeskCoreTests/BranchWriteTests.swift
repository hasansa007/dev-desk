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

    func testTheConfirmationCountsWhatWouldBeLost() {
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 1),
                       "Delete the branch feat/x and the 1 commit it holds that the base branch does not?")
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 6),
                       "Delete the branch feat/x and the 6 commits it holds that the base branch does not?")
        XCTAssertEqual(BranchWrite.confirmation(branch: "feat/x", unmerged: 0),
                       "Delete the branch feat/x? Its commits are already in the base branch.")
    }
}

final class BranchAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNothingIsStaleWithoutADate() {
        XCTAssertFalse(BranchAge.isStale(nil, now: now), "a card with no branch is not a stale branch")
    }

    func testTwoWeeksIsTheLine() {
        XCTAssertFalse(BranchAge.isStale(now.addingTimeInterval(-13 * 86_400), now: now))
        XCTAssertTrue(BranchAge.isStale(now.addingTimeInterval(-14 * 86_400), now: now))
    }

    func testTheLabelShortensAsItAges() {
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-600), now: now), "10 min ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-7200), now: now), "2 h ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-8 * 86_400), now: now), "8 d ago")
        XCTAssertEqual(BranchAge.label(now.addingTimeInterval(-90 * 86_400), now: now), "3 mo ago")
    }
}
