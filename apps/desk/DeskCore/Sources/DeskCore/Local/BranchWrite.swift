import Foundation

public enum BranchWriteError: Error, Equatable, LocalizedError {
    case notThisRepository
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notThisRepository:
            return "This project has no folder on disk, so there is no branch to delete."
        case .failed(let detail):
            return "git could not delete the branch: \(detail)"
        }
    }
}

/// Deleting a branch is the first thing Dev Desk destroys rather than moves, so it is bounded the way a
/// tracker write is: one command, arguments built here, and a name that cannot be read as an option.
public struct BranchWrite {
    let directory: URL
    let runner: CommandRunner

    public init(directory: URL, runner: CommandRunner = ProcessRunner()) {
        self.directory = directory
        self.runner = runner
    }

    /// `-d` refuses a branch whose commits are not in the base; `-D` is reached only after the developer has
    /// typed the branch's own name. `--` ends the options, so a branch called `--force` is still just a name.
    public static func arguments(branch: String, force: Bool) -> [String]? {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(" "), !name.hasPrefix("refs/") else { return nil }
        return ["branch", force ? "-D" : "-d", "--", name]
    }

    /// An uncounted branch is not a branch counted at zero, so nil asks for the name (ADR 0022).
    public static func requiresTypedName(unmerged: Int?) -> Bool { unmerged.map { $0 > 0 } ?? true }

    public static func confirmation(branch: String, unmerged: Int?) -> String {
        guard let unmerged else {
            return "Delete the branch \(branch)? Dev Desk has not counted what it holds that the base branch does not."
        }
        return unmerged > 0
            ? "Delete the branch \(branch) and the \(unmerged) commit\(unmerged == 1 ? "" : "s") it holds that the base branch does not?"
            : "Delete the branch \(branch)? Its commits are already in the base branch."
    }

    public func delete(branch: String, force: Bool) async throws {
        guard let arguments = Self.arguments(branch: branch, force: force) else {
            throw BranchWriteError.failed("\(branch) is not a name git branch would accept")
        }
        let result: CommandResult
        do {
            // `branch -D` fires reference-transaction hooks, so the delete is hardened like every other git call.
            result = try await runner.run("git", GitCommand.read(arguments), in: directory, timeout: CommandTimeout.git)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw BranchWriteError.failed(error.localizedDescription)
        }
        guard result.succeeded else {
            throw BranchWriteError.failed(GitOutput.lastNonEmptyLine(result.stderr) ?? "git exited with status \(result.status)")
        }
    }
}
