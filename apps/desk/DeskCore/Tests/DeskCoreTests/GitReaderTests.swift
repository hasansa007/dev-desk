import XCTest
@testable import DeskCore

final class GitReaderTests: XCTestCase {
    /// A repo whose branch `feat` was merged on the remote, as a pull request merged on GitHub is, while the local `main` stayed behind.
    private func repoMergedOnlyOnTheRemote() throws -> (TempGitRepo, URL) {
        let parent = try TempGitRepo()
        try parent.git("init", "-q", "--bare", "origin.git")
        try parent.git("init", "-q", "-b", "main", "app")
        try parent.write("app/README.md", "hello\n")
        try parent.git("-C", "app", "add", "-A")
        try parent.git("-C", "app", "commit", "-q", "-m", "initial")
        try parent.git("-C", "app", "remote", "add", "origin", parent.url.appendingPathComponent("origin.git").path)
        try parent.git("-C", "app", "push", "-q", "origin", "main")
        try parent.git("-C", "app", "switch", "-q", "-c", "feat")
        try parent.write("app/feature.txt", "done\n")
        try parent.git("-C", "app", "add", "-A")
        try parent.git("-C", "app", "commit", "-q", "-m", "feature")
        try parent.git("-C", "app", "switch", "-q", "--detach", "main")
        try parent.git("-C", "app", "merge", "-q", "--no-ff", "-m", "Merge feat", "feat")
        try parent.git("-C", "app", "push", "-q", "origin", "HEAD:main")
        try parent.git("-C", "app", "switch", "-q", "feat")
        return (parent, parent.url.appendingPathComponent("app", isDirectory: true))
    }

    func testBranchesAreMeasuredAgainstOriginsBaseNotAStaleLocalCopy() async throws {
        let (parent, root) = try repoMergedOnlyOnTheRemote()
        let facts = await GitReader(root: root, runner: ProcessRunner()).read(toplevel: root.path, currentBranch: "feat")
        XCTAssertEqual(facts.baseRef, "refs/remotes/origin/main")
        XCTAssertEqual(facts.branches.first { $0.name == "feat" }?.unmerged, 0, "feat is inside origin/main, however far local main lags")
        _ = parent
    }

    func testEachBranchCarriesTheCommitItPointsAt() async throws {
        let (parent, root) = try repoMergedOnlyOnTheRemote()
        let feat = try parent.gitOutput(["-C", root.path, "rev-parse", "refs/heads/feat"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = await GitReader(root: root, runner: ProcessRunner()).read(toplevel: root.path, currentBranch: "feat")
        XCTAssertEqual(facts.branches.first { $0.name == "feat" }?.head, feat)
    }
}
