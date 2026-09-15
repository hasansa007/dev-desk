import XCTest
@testable import DeskCore

final class TrackerWriteTests: XCTestCase {
    private let slug = "owner/repo"
    private let directory = URL(fileURLWithPath: "/repo", isDirectory: true)

    private func write(_ runner: FakeRunner) -> TrackerWrite {
        TrackerWrite(slug: slug, directory: directory, runner: runner)
    }

    func testQueueSetsTheMilestoneAndNamesTheRepository() async throws {
        let runner = FakeRunner(["gh issue edit 63 --repo owner/repo --milestone 1.4": .ok()])
        try await write(runner).perform(issue: 63, action: .queue(milestone: "1.4"))
        XCTAssertEqual(runner.keys, ["gh issue edit 63 --repo owner/repo --milestone 1.4"])
        XCTAssertEqual(runner.calls.first?.timeout, CommandTimeout.gh)
    }

    func testBacklogRemovesTheMilestone() async throws {
        let runner = FakeRunner(["gh issue edit 63 --repo owner/repo --remove-milestone": .ok()])
        try await write(runner).perform(issue: 63, action: .backlog)
        XCTAssertEqual(runner.keys, ["gh issue edit 63 --repo owner/repo --remove-milestone"])
    }

    func testCancelClosesAsNotPlannedAndWritesTheReasonAsAComment() async throws {
        let key = "gh issue close 63 --repo owner/repo --reason not planned --comment Superseded by #70"
        let runner = FakeRunner([key: .ok()])
        try await write(runner).perform(issue: 63, action: .cancel(reason: "  Superseded by #70  "))
        XCTAssertEqual(runner.keys, [key])
    }

    func testACancelWithNoReasonWritesNothing() async {
        let runner = FakeRunner()
        do {
            try await write(runner).perform(issue: 63, action: .cancel(reason: "   "))
            XCTFail("a cancel with no reason must be refused")
        } catch {
            XCTAssertEqual(error as? TrackerWriteError, .cancelNeedsReason)
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testQueueingWithNoMilestoneWritesNothing() async {
        let runner = FakeRunner()
        do {
            try await write(runner).perform(issue: 63, action: .queue(milestone: ""))
            XCTFail("queueing with no milestone must be refused")
        } catch {
            XCTAssertEqual(error as? TrackerWriteError, .noActiveMilestone)
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testAFailedWriteReportsWhatGhSaid() async {
        let runner = FakeRunner(["gh issue edit 63 --repo owner/repo --remove-milestone":
                                    .failed(1, stderr: "HTTP 403: Resource not accessible by integration\n")])
        do {
            try await write(runner).perform(issue: 63, action: .backlog)
            XCTFail("a non-zero gh exit must throw")
        } catch {
            XCTAssertEqual(error as? TrackerWriteError, .failed("HTTP 403: Resource not accessible by integration"))
        }
    }

    func testEveryConfirmationNamesTheRepositoryAndNumber() {
        for action in [TrackerAction.queue(milestone: "1.4"), .backlog, .cancel(reason: "why"), .draftPullRequest] {
            XCTAssertTrue(TrackerWrite.confirmation(issue: 63, slug: slug, action: action).contains("owner/repo#63"),
                          "\(action) must name the repository and number")
        }
    }

    /// The Review card's one backwards move (ADR 0035): the number is the pull request's, and the write
    /// converts it back to a draft rather than editing any issue.
    func testConvertingBackToADraftUndoesPrReady() {
        XCTAssertEqual(TrackerWrite.arguments(issue: 41, slug: "o/r", action: .draftPullRequest),
                       ["pr", "ready", "41", "--repo", "o/r", "--undo"])
    }

    func testTheDraftConfirmationSaysWhatLeavesReview() {
        XCTAssertEqual(TrackerWrite.confirmation(issue: 41, slug: "o/r", action: .draftPullRequest),
                       "Convert o/r#41 back to a draft, so it leaves Review?")
    }

    /// The Done column is git's (ADR 0011). This write follows git rather than asserting over it, so it carries
    /// no reason prose: there is nothing to explain when the commits are already in the base.
    func testMarkingCompletedClosesWithGitHubsOwnCompletedReason() {
        XCTAssertEqual(TrackerWrite.arguments(issue: 12, slug: "o/r", action: .complete),
                       ["issue", "close", "12", "--repo", "o/r", "--reason", "completed"])
    }

    func testTheCompletedConfirmationSaysWhyItIsAllowed() {
        XCTAssertEqual(TrackerWrite.confirmation(issue: 12, slug: "o/r", action: .complete),
                       "Close o/r#12 as completed? Its work is already in the base branch.")
    }
}
