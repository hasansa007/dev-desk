import XCTest
@testable import DeskCore

final class OriginSyncTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/repo")

    private func runner(refs: String, counts: [String: String], toplevel: String = "/tmp/repo", status: String = "") -> FakeRunner {
        let runner = FakeRunner([
            FakeRunner.gitRead("remote"): .ok("origin\n"),
            FakeRunner.gitRead("fetch --no-tags --prune origin"): .ok(),
            FakeRunner.gitRead("for-each-ref --format=%(refname:short)%09%(upstream)%09%(worktreepath) refs/heads"): .ok(refs),
            FakeRunner.gitRead("for-each-ref --format=%(refname) refs/remotes/origin"): .ok("refs/remotes/origin/staging\nrefs/remotes/origin/main\nrefs/remotes/origin/feature\n"),
            FakeRunner.gitRead("rev-parse --show-toplevel"): .ok(toplevel + "\n"),
            FakeRunner.gitRead("status --porcelain --untracked-files=no"): .ok(status),
        ])
        for (branch, count) in counts {
            runner.script(FakeRunner.gitRead("rev-list --left-right --count refs/heads/\(branch)...refs/remotes/origin/\(branch)"), .ok(count))
            runner.script(FakeRunner.gitRead("rev-parse refs/heads/\(branch)"), .ok("abc\n"))
            runner.script(FakeRunner.gitRead("update-ref -m dev desk: fast-forward from origin refs/heads/\(branch) refs/remotes/origin/\(branch) abc"), .ok())
        }
        runner.script(FakeRunner.gitRead("merge --ff-only --no-edit refs/remotes/origin/main"), .ok())
        return runner
    }

    func testOnlyABranchStrictlyBehindAndSafeToMoveIsFastForwarded() async {
        let refs = """
        staging\trefs/remotes/origin/staging\t
        feature\t\t
        main\trefs/remotes/origin/main\t/tmp/repo
        local-only\t\t
        """
        // staging is behind (moved), feature has its own commit (kept), main is checked out here and clean (merged ff-only).
        let sync = await OriginSync(root: root, runner: runner(refs: refs, counts: ["staging": "0\t44", "feature": "1\t3", "main": "0\t2"])).run()
        XCTAssertTrue(sync.fetched)
        XCTAssertEqual(sync.fastForwarded, ["staging", "main"])
    }

    func testACheckoutWithUncommittedChangesOrInAnotherWorktreeIsNeverMoved() async {
        let dirty = runner(refs: "main\trefs/remotes/origin/main\t/tmp/repo\n", counts: ["main": "0\t2"], status: " M a.swift")
        let dirtyResult = await OriginSync(root: root, runner: dirty).run()
        XCTAssertEqual(dirtyResult.fastForwarded, [])
        XCTAssertFalse(dirty.keys.contains(FakeRunner.gitRead("merge --ff-only --no-edit refs/remotes/origin/main")))
        let elsewhere = runner(refs: "main\trefs/remotes/origin/main\t/tmp/agent-worktree\n", counts: ["main": "0\t2"])
        let elsewhereResult = await OriginSync(root: root, runner: elsewhere).run()
        XCTAssertEqual(elsewhereResult.fastForwarded, [])
    }

    func testNoOriginFetchesNothing() async {
        let runner = FakeRunner([FakeRunner.gitRead("remote"): .ok("upstream\n")])
        let result = await OriginSync(root: root, runner: runner).run()
        XCTAssertFalse(result.fetched)
        XCTAssertEqual(runner.keys, [FakeRunner.gitRead("remote")])
    }

    func testReportTreeListsOnlyTheFoldersOwnMarkdownBlobs() {
        let output = [
            "100644 blob aaa111 120\tdocs/findings/2026-09-17.md",
            "100644 blob bbb222 50\tdocs/findings/notes.txt",
            "040000 tree ccc333 -\tdocs/findings/old",
            "120000 blob ddd444 30\tdocs/findings/link.md",
        ].joined(separator: "\0")
        XCTAssertEqual(ReportTree.entries(output), [ReportTree.Entry(name: "2026-09-17.md", object: "aaa111", size: 120)])
    }

    func testAReportDoorFolderIsNamedForTheProjectDoorAndMoment() {
        let date = ISO8601DateFormatter().date(from: "2026-09-17T01:02:03Z")!
        let name = FreshBaseWorktree.folderName(project: "StudyHub Deploy", door: "findings", at: date)
        XCTAssertTrue(name.hasPrefix("studyhub-deploy-findings-20260917-"))
        XCTAssertEqual(ShellQuote.single("it's"), "'it'\\''s'")
    }
}
