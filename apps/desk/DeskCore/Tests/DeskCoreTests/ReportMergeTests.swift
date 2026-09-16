import XCTest
@testable import DeskCore

final class ReportMergeTests: XCTestCase {
    private let repo = URL(fileURLWithPath: "/tmp/repo")
    private let scratch = URL(fileURLWithPath: "/tmp/scratch")

    private func key(_ arguments: String) -> String { FakeRunner.gitRead(arguments) }

    func testMergesIntoOriginsBaseFromAThrowawayWorktreeAndPushes() async throws {
        let runner = FakeRunner([
            key("fetch --no-tags origin +refs/heads/staging:refs/remotes/origin/staging"): .ok(),
            key("worktree add --detach -- /tmp/scratch refs/remotes/origin/staging"): .ok(),
            (["git"] + GitCommand.commitFlags + ["merge", "--no-ff", "-m"]).joined(separator: " ")
                + " Merge report findings/2026-09-17 into staging refs/heads/findings/2026-09-17": .ok(),
            key("push origin HEAD:refs/heads/staging"): .ok(),
            key("worktree remove --force -- /tmp/scratch"): .ok(),
        ])
        try await ReportMerge(directory: repo, runner: runner, scratch: scratch).merge(branch: "findings/2026-09-17", base: "staging")
        XCTAssertEqual(runner.calls.filter { $0.key.contains(" merge ") || $0.key.contains(" push ") }.map(\.directory), [scratch, scratch])
        XCTAssertEqual(runner.keys.last, key("worktree remove --force -- /tmp/scratch"))
        // A repo that signs commits (gpg.format ssh) refuses the merge if its signer is blanked.
        let merge = try XCTUnwrap(runner.keys.first { $0.contains(" merge ") })
        XCTAssertFalse(merge.contains("gpg."))
        XCTAssertTrue(merge.contains("core.hooksPath=/dev/null"))
    }

    func testAMergeThatFailsStillRemovesTheWorktreeAndPushesNothing() async {
        let runner = FakeRunner([
            key("fetch --no-tags origin +refs/heads/staging:refs/remotes/origin/staging"): .ok(),
            key("worktree add --detach -- /tmp/scratch refs/remotes/origin/staging"): .ok(),
            key("worktree remove --force -- /tmp/scratch"): .ok(),
        ])
        do {
            try await ReportMerge(directory: repo, runner: runner, scratch: scratch).merge(branch: "findings/x", base: "staging")
            XCTFail("an unscripted merge fails")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Could not merge findings/x into staging"))
        }
        XCTAssertFalse(runner.keys.contains(key("push origin HEAD:refs/heads/staging")))
        XCTAssertEqual(runner.keys.last, key("worktree remove --force -- /tmp/scratch"))
    }

    func testTheSubjectRoundTripsAndOnlyAnOriginBaseIsPushable() {
        XCTAssertEqual(ReportMerge.branch(fromSubject: ReportMerge.subject(branch: "findings/2026-09-17", base: "staging")), "findings/2026-09-17")
        XCTAssertNil(ReportMerge.branch(fromSubject: "Merge pull request #7 from a/b"))
        XCTAssertEqual(ReportMerge.originBase("refs/remotes/origin/staging"), "staging")
        XCTAssertNil(ReportMerge.originBase("refs/heads/staging"))
        XCTAssertEqual(GitOutput.reportMerges("Merge report a/b into main\u{1f}2026-09-17T01:00:00Z\nMerge report a/b into main\u{1f}x\nOther\u{1f}y"),
                       [ReportMergeRecord(branch: "a/b", date: "2026-09-17T01:00:00Z")])
    }
}
