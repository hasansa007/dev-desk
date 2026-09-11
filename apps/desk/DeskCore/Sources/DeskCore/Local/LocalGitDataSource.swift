import Foundation

public enum LocalProjectError: Error, Equatable, LocalizedError {
    case folderMissing(String)
    public var errorDescription: String? {
        switch self {
        case .folderMissing(let path): return "The folder \(path) no longer exists."
        }
    }
}

public struct LocalGitDataSource: ProjectDataSource {
    public let root: URL
    let runner: CommandRunner

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public func load() async throws -> ProjectSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { throw LocalProjectError.folderMissing(root.path) }
        let unread = "Not read yet."
        return ProjectSnapshot(project: await identity(), isDemo: false, board: .unavailable(unread), boardNote: "",
                               findings: .unavailable(unread), roadmap: .unavailable(unread), decisions: .unavailable(unread),
                               connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                               insights: .unavailable(unread))
    }

    func identity() async -> ProjectInfo {
        async let branch = git(["rev-parse", "--abbrev-ref", "HEAD"])
        async let remote = git(["remote", "get-url", "origin"])
        async let head = git(["rev-parse", "--short", "HEAD"])
        return ProjectInfo(name: root.lastPathComponent, displayPath: Self.abbreviate(root.path),
                           branch: await branch ?? "", remote: await remote.map(GitRemote.display), headRevision: await head)
    }

    /// Trimmed stdout of a successful git call; nil when git fails or is missing.
    func git(_ arguments: [String]) async -> String? {
        guard let result = try? await runner.run("git", arguments, in: root, timeout: CommandTimeout.git), result.succeeded else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
