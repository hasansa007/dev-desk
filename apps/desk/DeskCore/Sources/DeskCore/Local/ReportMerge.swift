import Foundation

public enum ReportMergeError: Error, Equatable, LocalizedError {
    case notThisRepository
    case noOriginBase
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notThisRepository: return "This project has no folder on disk, so there is no branch to merge."
        case .noOriginBase: return "The base branch has no copy on origin, so there is nowhere to push the merge."
        case .failed(let detail): return detail
        }
    }
}

/// A door's finished report is approved by merging it: into origin's copy of the base, from a throwaway worktree,
/// so neither the checkout you are standing in nor a local base that has drifted from origin is ever touched.
public struct ReportMerge {
    let directory: URL
    let runner: CommandRunner
    let scratch: URL

    public init(directory: URL, runner: CommandRunner = ProcessRunner(),
                scratch: URL = FileManager.default.temporaryDirectory.appendingPathComponent("devdesk-merge-\(UUID().uuidString)")) {
        self.directory = directory
        self.runner = runner
        self.scratch = scratch
    }

    /// The merge commit's subject, and what the board reads back to keep the approved report in Done.
    public static let subjectPrefix = "Merge report "

    public static func subject(branch: String, base: String) -> String { "\(subjectPrefix)\(branch) into \(base)" }

    /// The branch a merge subject names, or nil for any other commit.
    static func branch(fromSubject subject: String) -> String? {
        guard subject.hasPrefix(subjectPrefix) else { return nil }
        let rest = subject.dropFirst(subjectPrefix.count)
        guard let into = rest.range(of: " into ") else { return nil }
        let name = String(rest[..<into.lowerBound])
        return name.isEmpty ? nil : name
    }

    /// `refs/remotes/origin/<name>` → `<name>`; a base with no origin copy has nowhere to push.
    public static func originBase(_ baseRef: String?) -> String? {
        let prefix = "refs/remotes/origin/"
        guard let baseRef, baseRef.hasPrefix(prefix) else { return nil }
        let name = String(baseRef.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }

    public static func confirmation(branch: String, base: String, commits: Int?, files: Int) -> String {
        let held = commits.map { "\($0) commit\($0 == 1 ? "" : "s"), " } ?? ""
        return "Merge \(branch) (\(held)\(files) file\(files == 1 ? "" : "s")) into \(base) on origin and push? "
            + "The card moves to Done once origin has it."
    }

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && !name.contains(" ") && !name.hasPrefix("refs/")
    }

    public func merge(branch: String, base: String) async throws {
        guard Self.valid(branch), Self.valid(base) else { throw ReportMergeError.failed("\(branch) or \(base) is not a branch name git would accept") }
        let remoteBase = "refs/remotes/origin/\(base)"
        try await git(["fetch", "--no-tags", "origin", "+refs/heads/\(base):\(remoteBase)"], timeout: CommandTimeout.worktreeAdd,
                      failure: "Could not fetch \(base) from origin")
        try await git(["worktree", "add", "--detach", "--", scratch.path, remoteBase], timeout: CommandTimeout.worktreeAdd,
                      failure: "Could not open a worktree on origin/\(base)")
        do {
            try await git(["merge", "--no-ff", "-m", Self.subject(branch: branch, base: base), "refs/heads/\(branch)"],
                          signed: true, in: scratch, timeout: CommandTimeout.worktreeAdd, failure: "Could not merge \(branch) into \(base)")
            try await git(["push", "origin", "HEAD:refs/heads/\(base)"], in: scratch, timeout: CommandTimeout.clone,
                          failure: "The merge was made but origin refused the push")
            // The push moves origin's ref; the tracking ref the board counts against is brought along with it.
            _ = try? await run(["fetch", "--no-tags", "origin", "+refs/heads/\(base):\(remoteBase)"], in: directory, timeout: CommandTimeout.worktreeAdd)
        } catch {
            await removeScratch()
            throw error
        }
        await removeScratch()
    }

    private func removeScratch() async {
        _ = try? await run(["worktree", "remove", "--force", "--", scratch.path], in: directory, timeout: CommandTimeout.git)
    }

    private func git(_ arguments: [String], signed: Bool = false, in folder: URL? = nil, timeout: TimeInterval, failure: String) async throws {
        let result: CommandResult
        do {
            result = try await run(arguments, signed: signed, in: folder ?? directory, timeout: timeout)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw ReportMergeError.failed("\(failure): \(error.localizedDescription)")
        }
        guard result.succeeded else {
            let reason = GitOutput.lastNonEmptyLine(result.stderr) ?? GitOutput.lastNonEmptyLine(result.stdout) ?? "git exited with status \(result.status)"
            throw ReportMergeError.failed("\(failure): \(reason)")
        }
    }

    private func run(_ arguments: [String], signed: Bool = false, in folder: URL, timeout: TimeInterval) async throws -> CommandResult {
        try await runner.run("git", signed ? GitCommand.commit(arguments) : GitCommand.read(arguments), in: folder, timeout: timeout)
    }
}
