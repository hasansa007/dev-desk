import Foundation

/// The project folder is not on its base branch. Work belongs in worktrees (a branch per task or process), so a folder
/// left on another branch is a mistake to undo — and what Findings, the board and every fresh worktree read as "the
/// project" is then that branch, not the base.
public struct FolderOffBase: Hashable {
    public let branch: String
    public let base: String
    /// Tracked changes that are not committed. Switching back is only offered without them.
    public let isDirty: Bool

    public init(branch: String, base: String, isDirty: Bool) {
        self.branch = branch
        self.base = base
        self.isDirty = isDirty
    }

    /// A branch that can live in a worktree of its own. Production and a detached HEAD are only ever switched away from.
    public var canMoveToWorktree: Bool { branch != "HEAD" && !OriginSync.neverMoved.contains(branch) }
}

/// The two ways back to base. Every step is a git command git itself refuses when it would lose work.
public struct FolderRestore {
    let root: URL
    let runner: CommandRunner

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    /// `git switch <base>`, creating the local base from origin when there is none. git refuses over uncommitted changes.
    public func switchToBase(_ base: String) async throws {
        let hasLocal = (try? await git(["show-ref", "--verify", "--quiet", "refs/heads/\(base)"]))?.succeeded ?? false
        let arguments = hasLocal ? ["switch", base] : ["switch", "-c", base, "--track", "origin/\(base)"]
        try await require(arguments, "Could not switch the folder to \(base)")
    }

    /// Moves `branch` out of the project folder into a worktree of its own, carrying its uncommitted tracked changes:
    /// they are stashed under a unique message, the folder switches to base, the worktree is added, and the stash is
    /// applied there — by its commit, never `stash@{0}`, since the stash list is shared — then dropped. Untracked files
    /// stay in the project folder, where git keeps them whatever branch it is on.
    public func moveToWorktree(branch: String, base: String, worktree: URL) async throws {
        let status = try await git(["status", "--porcelain", "--untracked-files=no"])
        var stash: String?
        if !status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let message = "dev desk: move \(branch) to a worktree \(UUID().uuidString)"
            try await require(["stash", "push", "-m", message], "Could not set \(branch)'s changes aside")
            let list = try await git(["stash", "list", "--format=%H %gs"])
            stash = GitOutput.lines(list.stdout).first { $0.hasSuffix(message) }.map { String($0.prefix(while: { $0 != " " })) }
            guard stash != nil else { throw ReportMergeError.failed("\(branch)'s changes were stashed but the stash could not be found again; nothing else was changed") }
        }
        do {
            try await switchToBase(base)
        } catch {
            if let stash { _ = try? await git(["stash", "apply", stash]) }
            throw error
        }
        try FileManager.default.createDirectory(at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await require(["worktree", "add", "--", worktree.path, branch],
                          "The folder is on \(base), but \(branch) could not be added as a worktree" + (stash.map { "; its changes are kept in stash \($0)" } ?? ""))
        await EnvFiles.copy(from: root, to: worktree, runner: runner)
        guard let stash else { return }
        let apply = try await git(["stash", "apply", stash], in: worktree)
        guard apply.succeeded else {
            throw ReportMergeError.failed("\(branch) is in its worktree, but its changes did not apply cleanly; they are kept in stash \(stash)")
        }
        // Dropped by position, found again by commit: another session may have pushed a stash since.
        let list = try await git(["stash", "list", "--format=%H"])
        if let index = GitOutput.lines(list.stdout).firstIndex(of: stash) {
            _ = try? await git(["stash", "drop", "stash@{\(index)}"])
        }
    }

    private func require(_ arguments: [String], _ failure: String) async throws {
        let result = try await git(arguments)
        guard result.succeeded else {
            throw ReportMergeError.failed("\(failure): \(GitOutput.lastNonEmptyLine(result.stderr) ?? "git exited with status \(result.status)")")
        }
    }

    private func git(_ arguments: [String], in folder: URL? = nil) async throws -> CommandResult {
        try await runner.run("git", GitCommand.read(arguments), in: folder ?? root, timeout: CommandTimeout.worktreeAdd)
    }
}
