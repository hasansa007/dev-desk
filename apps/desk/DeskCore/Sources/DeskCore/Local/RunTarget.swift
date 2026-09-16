import Foundation

/// Where a run of the project goes: the project folder, or a session's own worktree — and which branch that is,
/// so a play button and a run's tab can say what version they run.
public struct RunTarget: Equatable {
    public let folder: URL
    public let branch: String
    public let isProjectFolder: Bool

    public init(folder: URL, branch: String, isProjectFolder: Bool) {
        self.folder = folder
        self.branch = branch
        self.isProjectFolder = isProjectFolder
    }

    /// The branch checked out in `folder`, read from git's own files rather than a process: a worktree's `.git`
    /// is a file naming its gitdir, the project folder's is a directory, and HEAD is a ref or a detached commit.
    public static func branch(in folder: URL) -> String {
        let dotGit = folder.appendingPathComponent(".git")
        var gitDir = dotGit
        if let text = try? String(contentsOf: dotGit, encoding: .utf8), text.hasPrefix("gitdir:") {
            let path = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return "unknown" }
        return head.hasPrefix("ref: refs/heads/") ? String(head.dropFirst("ref: refs/heads/".count)) : "detached"
    }
}

/// A run that would replace the live run of the same configuration in another folder — asked, never done silently:
/// both would listen on the same port, so the second only works once the first has stopped.
public struct RunReplacement: Equatable, Identifiable {
    public var id: String { liveSessionID + folderPath }
    public let configurationID: String?
    public let intent: ProjectRunIntent
    public let folderPath: String
    public let branch: String
    public let liveSessionID: String
    public let liveBranch: String
    public let configurationName: String

    public init(configurationID: String?, intent: ProjectRunIntent, folderPath: String, branch: String,
                liveSessionID: String, liveBranch: String, configurationName: String) {
        self.configurationID = configurationID
        self.intent = intent
        self.folderPath = folderPath
        self.branch = branch
        self.liveSessionID = liveSessionID
        self.liveBranch = liveBranch
        self.configurationName = configurationName
    }
}

/// ⌘R and ⌘. are menu commands, and the terminal registry that runs them belongs to the window: the menu asks, the
/// window acts. The id makes a second press of the same command a change the window hears.
public struct WindowCommandRequest: Equatable {
    public enum Command: Equatable { case run, stop }
    public let command: Command
    public let id = UUID()

    public init(_ command: Command) { self.command = command }
}

/// The untracked environment files a run needs, copied from the project folder into a new worktree — `git worktree
/// add` carries tracked files only, so without this a run in a fresh worktree starts with no `.env.local`.
/// Copied, not linked: a worktree's settings are its own to change.
public enum EnvFiles {
    static let maxBytes = 1_048_576

    /// `ls-files -z --others --ignored --exclude-standard --directory` entries whose file name starts `.env`.
    /// An ignored directory is collapsed to one entry ending in `/` and skipped, so `node_modules` is never listed.
    static func paths(_ output: String) -> [String] {
        output.components(separatedBy: "\0").filter { path in
            guard !path.isEmpty, !path.hasSuffix("/"), !path.hasPrefix("/"), !path.contains("..") else { return false }
            return (path as NSString).lastPathComponent.hasPrefix(".env")
        }
    }

    /// Copies each into `worktree` where nothing is there yet; returns the relative paths copied.
    @discardableResult
    public static func copy(from projectRoot: URL, to worktree: URL, runner: CommandRunner) async -> [String] {
        guard let listing = try? await runner.run("git", GitCommand.read(["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"]),
                                                  in: projectRoot, timeout: CommandTimeout.git),
              listing.succeeded else { return [] }
        var copied: [String] = []
        let files = FileManager.default
        for path in paths(listing.stdout) {
            let source = projectRoot.appendingPathComponent(path)
            let target = worktree.appendingPathComponent(path)
            guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= maxBytes,
                  !files.fileExists(atPath: target.path) else { continue }
            do {
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.copyItem(at: source, to: target)
                copied.append(path)
            } catch {
                continue
            }
        }
        return copied
    }
}
