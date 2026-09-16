import Foundation

/// Where a report door runs: a new worktree detached at origin's base, fetched just before. A report written from
/// a stale checkout describes code that is no longer there, and a door that switches the developer's own checkout
/// to cut its branch moves the ground under whatever they, or an agent, had open in it.
public struct FreshBaseWorktree {
    /// The doors that read the whole project and end in a report.
    public static let doors: Set<String> = ["findings", "ideation", "roadmap"]

    let projectRoot: URL
    let worktreeLocation: String
    let runner: CommandRunner
    let homeDirectory: URL

    public init(projectRoot: URL, worktreeLocation: String, runner: CommandRunner = ProcessRunner(),
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.projectRoot = projectRoot
        self.worktreeLocation = worktreeLocation
        self.runner = runner
        self.homeDirectory = homeDirectory
    }

    /// The folder to run in. Anything that stops the worktree — no origin, no base, a failed fetch or add — runs the door
    /// at the project root instead, with the reason, rather than not at all.
    public func prepare(door: String, now: Date = Date()) async -> TaskFolder {
        let fetch = try? await git(["fetch", "--no-tags", "origin"], in: projectRoot, timeout: CommandTimeout.worktreeAdd)
        guard let fetch, fetch.succeeded else {
            return atRoot("origin could not be fetched" + (fetch.flatMap { GitOutput.lastNonEmptyLine($0.stderr) }.map { ": \($0)" } ?? ""))
        }
        guard let remote = try? await git(["branch", "-r", "--format=%(refname:short)"], in: projectRoot, timeout: CommandTimeout.git),
              remote.succeeded, let base = GitOutput.preferredBase(remoteBranches: remote.stdout) else {
            return atRoot("origin has no base branch (\(GitOutput.baseCandidates.joined(separator: ", ")))")
        }
        guard let location = expandedLocation else { return atRoot("the worktree location is not an absolute folder") }
        let path = location.appendingPathComponent(Self.folderName(project: projectRoot.lastPathComponent, door: door, at: now), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        } catch {
            return atRoot(error.localizedDescription)
        }
        let add = try? await git(["worktree", "add", "--detach", "--", path.path, "refs/remotes/origin/\(base)"],
                                 in: projectRoot, timeout: CommandTimeout.worktreeAdd)
        guard let add, add.succeeded else {
            return atRoot("git could not add a worktree on origin/\(base)" + (add.flatMap { GitOutput.lastNonEmptyLine($0.stderr) }.map { ": \($0)" } ?? ""))
        }
        return TaskFolder(url: path, note: nil, created: true)
    }

    static func folderName(project: String, door: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let slug = { (text: String) in String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }) }
        return "\(slug(project))-\(slug(door))-\(formatter.string(from: date))"
    }

    private func atRoot(_ reason: String) -> TaskFolder {
        TaskFolder(url: projectRoot, note: "This run opens at the project root, not on a fresh origin base: \(reason).", created: false)
    }

    private var expandedLocation: URL? {
        if worktreeLocation == "~" { return homeDirectory }
        if worktreeLocation.hasPrefix("~/") { return homeDirectory.appendingPathComponent(String(worktreeLocation.dropFirst(2)), isDirectory: true) }
        return worktreeLocation.hasPrefix("/") ? URL(fileURLWithPath: worktreeLocation, isDirectory: true) : nil
    }

    private func git(_ arguments: [String], in folder: URL, timeout: TimeInterval) async throws -> CommandResult {
        try await runner.run("git", GitCommand.read(arguments), in: folder, timeout: timeout)
    }
}

/// POSIX single quotes: everything inside is literal, and a quote inside is closed, escaped and reopened.
public enum ShellQuote {
    public static func single(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
