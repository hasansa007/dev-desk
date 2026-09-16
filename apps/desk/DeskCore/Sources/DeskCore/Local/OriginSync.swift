import Foundation

/// What an action brings in from origin before the board is read again: a fetch, then every local branch moved
/// forward that can be moved without losing anything. It never merges, never touches a branch with commits of its
/// own, and never moves a checkout that has uncommitted changes or that another worktree is working in.
public struct OriginSync {
    let root: URL
    let runner: CommandRunner

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public struct Result: Equatable {
        /// False when there is no origin, or the fetch failed; nothing was moved then.
        public var fetched = false
        public var fastForwarded: [String] = []
        public var failure: String?
    }

    /// A local branch and the origin branch it can follow: its upstream, or origin's branch of the same name.
    struct Candidate: Equatable {
        let name: String
        let remote: String
        let worktree: String?
    }

    public func run() async -> Result {
        var result = Result()
        guard let remote = await output(["remote"]), GitOutput.lines(remote).contains("origin") else { return result }
        let fetch = try? await runner.run("git", GitCommand.read(["fetch", "--no-tags", "--prune", "origin"]),
                                          in: root, timeout: CommandTimeout.worktreeAdd)
        guard let fetch, fetch.succeeded else {
            result.failure = fetch.flatMap { GitOutput.lastNonEmptyLine($0.stderr) } ?? "git fetch did not finish"
            return result
        }
        result.fetched = true
        guard let refs = await output(["for-each-ref", "--format=%(refname:short)%09%(upstream)%09%(worktreepath)", "refs/heads"]),
              let remotes = await output(["for-each-ref", "--format=%(refname)", "refs/remotes/origin"]) else { return result }
        let here = await output(["rev-parse", "--show-toplevel"])
        for candidate in Self.candidates(refs, remoteRefs: Set(GitOutput.lines(remotes))) {
            if await fastForward(candidate, toplevel: here) { result.fastForwarded.append(candidate.name) }
        }
        return result
    }

    /// `for-each-ref --format=%(refname:short)%09%(upstream)%09%(worktreepath)` lines, paired with the origin ref each can follow.
    static func candidates(_ refs: String, remoteRefs: Set<String>) -> [Candidate] {
        GitOutput.lines(refs).compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard let name = parts.first, !name.isEmpty, !name.hasPrefix("-") else { return nil }
            let upstream = parts.count > 1 ? parts[1] : ""
            let remote = upstream.hasPrefix("refs/remotes/origin/") ? upstream : "refs/remotes/origin/\(name)"
            guard remoteRefs.contains(remote) else { return nil }
            let worktree = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
            return Candidate(name: name, remote: remote, worktree: worktree)
        }
    }

    private func fastForward(_ candidate: Candidate, toplevel: String?) async -> Bool {
        let local = "refs/heads/\(candidate.name)"
        // Strictly behind: nothing of its own to lose, and something to gain.
        guard let counts = await output(["rev-list", "--left-right", "--count", "\(local)...\(candidate.remote)"]),
              let (ahead, behind) = Self.counts(counts), ahead == 0, behind > 0,
              let old = await output(["rev-parse", local]) else { return false }
        guard let worktree = candidate.worktree else {
            // Checked out nowhere: move the ref, and only from the commit just read.
            return await succeeds(["update-ref", "-m", "dev desk: fast-forward from origin", local, candidate.remote, old], in: root)
        }
        // Checked out elsewhere is someone's working folder, maybe an agent's: it is theirs to update.
        guard Self.same(worktree, toplevel) else { return false }
        guard let status = await output(["status", "--porcelain", "--untracked-files=no"], allowEmpty: true), status.isEmpty else { return false }
        return await succeeds(["merge", "--ff-only", "--no-edit", candidate.remote], in: root)
    }

    static func counts(_ text: String) -> (Int, Int)? {
        let parts = text.split(whereSeparator: { $0 == "\t" || $0 == " " }).compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private static func same(_ path: String, _ other: String?) -> Bool {
        guard let other else { return false }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == URL(fileURLWithPath: other).resolvingSymlinksInPath().path
    }

    private func succeeds(_ arguments: [String], in folder: URL) async -> Bool {
        (try? await runner.run("git", GitCommand.read(arguments), in: folder, timeout: CommandTimeout.git))?.succeeded ?? false
    }

    private func output(_ arguments: [String], allowEmpty: Bool = false) async -> String? {
        guard let result = try? await runner.run("git", GitCommand.read(arguments), in: root, timeout: CommandTimeout.git),
              result.succeeded else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty && !allowEmpty ? nil : text
    }
}
