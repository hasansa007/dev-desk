import Foundation

/// The bounded write set `dev:kanban` Phase 7 allows against a board. Delete is deliberately absent:
/// that tier keeps its hard gate in the door, where an epic's children are enumerated first.
public enum TrackerAction: Equatable, Hashable {
    case queue(milestone: String)
    case backlog
    case cancel(reason: String)
    /// Only offered where git already agrees the work landed — the board's Done column is git's (ADR 0011),
    /// so this closes the issue to match what git says, never to assert something git contradicts.
    case complete
}

public enum TrackerWriteError: Error, Equatable, LocalizedError {
    case cancelNeedsReason
    case noActiveMilestone
    case noRepository
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelNeedsReason:
            return "A cancel has to say why. A closed issue with no reason can't be told from one closed by accident."
        case .noActiveMilestone:
            return "This repository has no active milestone, so there is no queue to add to."
        case .noRepository:
            return "This project has no GitHub repository, so the tracker can't be written to."
        case .failed(let detail):
            return "gh could not write the change: \(detail)"
        }
    }
}

/// Writes a card's move to GitHub. Every write names `owner/repo` in its own arguments, never the ambient directory.
public struct TrackerWrite {
    let slug: String
    let directory: URL
    let runner: CommandRunner

    public init(slug: String, directory: URL, runner: CommandRunner = ProcessRunner()) {
        self.slug = slug
        self.directory = directory
        self.runner = runner
    }

    /// The exact `gh` arguments for an action, or nil when the action is missing what it needs.
    /// Verified 2026-09-12 against gh 2.92.0: `--milestone`, `--remove-milestone`, `--reason`, `--comment`.
    public static func arguments(issue: Int, slug: String, action: TrackerAction) -> [String]? {
        switch action {
        case .queue(let milestone):
            let title = milestone.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return ["issue", "edit", String(issue), "--repo", slug, "--milestone", title]
        case .backlog:
            return ["issue", "edit", String(issue), "--repo", slug, "--remove-milestone"]
        case .cancel(let reason):
            let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ["issue", "close", String(issue), "--repo", slug, "--reason", "not planned", "--comment", text]
        case .complete:
            return ["issue", "close", String(issue), "--repo", slug, "--reason", "completed"]
        }
    }

    /// What the confirmation asks before anything is written; Phase 7 requires the repository and number out loud.
    public static func confirmation(issue: Int, slug: String, action: TrackerAction) -> String {
        switch action {
        case .queue(let milestone):
            return "Add \(slug)#\(issue) to the milestone “\(milestone)”?"
        case .backlog:
            return "Remove \(slug)#\(issue) from its milestone, back to the backlog?"
        case .cancel:
            return "Close \(slug)#\(issue) as not planned, with your reason as a comment?"
        case .complete:
            return "Close \(slug)#\(issue) as completed? Its work is already in the base branch."
        }
    }

    public func perform(issue: Int, action: TrackerAction) async throws {
        guard let arguments = Self.arguments(issue: issue, slug: slug, action: action) else {
            throw action.missingInput
        }
        let result: CommandResult
        do {
            result = try await runner.run("gh", arguments, in: directory, timeout: CommandTimeout.gh)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw TrackerWriteError.failed(error.localizedDescription)
        }
        guard result.succeeded else {
            throw TrackerWriteError.failed(GitOutput.lastNonEmptyLine(result.stderr) ?? "gh exited with status \(result.status)")
        }
    }
}

extension TrackerAction {
    /// Which requirement an action failed to meet, so the refusal says what is missing rather than "invalid".
    var missingInput: TrackerWriteError {
        switch self {
        case .queue: return .noActiveMilestone
        case .backlog: return .failed("nothing to remove")
        case .cancel: return .cancelNeedsReason
        case .complete: return .failed("nothing to close")
        }
    }
}
