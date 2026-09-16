import XCTest
@testable import DeskCore

final class RunTargetTests: XCTestCase {
    func testOnlyUntrackedEnvFilesAreCopiedNeverACollapsedDirectory() {
        let listing = ["web/.env.local", "node_modules/", ".env", "web/.next/", "docs/notes.md", ".envrc", "../.env", ""].joined(separator: "\0")
        XCTAssertEqual(EnvFiles.paths(listing), ["web/.env.local", ".env", ".envrc"])
    }

    func testTheBranchIsReadFromAWorktreesGitdirAndFromTheProjectFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("runtarget-\(UUID().uuidString)")
        let project = base.appendingPathComponent("project"), worktree = base.appendingPathComponent("wt")
        let gitdir = project.appendingPathComponent(".git/worktrees/wt")
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "ref: refs/heads/staging\n".write(to: project.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/gh-12-fix\n".write(to: gitdir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(gitdir.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RunTarget.branch(in: project), "staging")
        XCTAssertEqual(RunTarget.branch(in: worktree), "gh-12-fix")
        try "0123abcd\n".write(to: gitdir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RunTarget.branch(in: worktree), "detached")
    }
}
