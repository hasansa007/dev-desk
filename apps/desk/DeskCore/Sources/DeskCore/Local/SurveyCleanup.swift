import Foundation

/// Clearing a project's survey history. A survey run appends a report; nothing has ever taken one away, so a
/// repository surveyed weekly accumulates every finding it ever had, and the screen's run picker becomes the
/// only thing standing between you and a year of them.
///
/// The newest report is never touched: it is the current picture, and a cleanup that takes it away is not a
/// cleanup, it is a loss. Reports go to the Trash, the same bargain `docs/backlog/` removal makes (ADR 0027) —
/// the app's own undo is the Finder's.
public enum SurveyCleanup {
    public static let folder = "docs/survey"

    /// The reports this cleanup would take, newest-first order applied first so the newest is the one kept.
    /// Only `.md` files sitting directly in `docs/survey/` count: a subfolder is somebody's own arrangement.
    public static func olderReports(in projectPath: String) -> [String] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let folderURL = root.appendingPathComponent(folder, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        let reports = names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted(by: >)
        return Array(reports.dropFirst())
    }

    /// Moves them to the Trash and returns how many went. A path that escaped `docs/survey/` is skipped rather
    /// than trusted: the names come from the folder, and this is the guard that keeps it that way.
    @discardableResult
    public static func trashOlderReports(in projectPath: String) throws -> Int {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let folderURL = root.appendingPathComponent(folder, isDirectory: true)
        var moved = 0
        for name in olderReports(in: projectPath) {
            let url = folderURL.appendingPathComponent(name)
            guard SafeFile.isInside(url, folderURL) else { continue }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            moved += 1
        }
        return moved
    }
}

/// What a reset clears. Each part is owned by someone different — the app, the window, the repository — so
/// each is asked for separately rather than one button meaning all three.
public struct SurveyResetOptions: Equatable {
    /// Findings set aside in this project. They live in the app, never in `docs/survey/`.
    public var ignoredFindings: Bool
    /// The screen's own state: which run is selected, which filter, whether ignored ones are shown.
    public var viewState: Bool
    /// Every report but the newest, to the Trash.
    public var olderReports: Bool
    /// Issues the survey filed that nobody started, to close as not planned with `closeReason` as the comment.
    public var closeIssues: [Int]
    public var closeReason: String

    public init(ignoredFindings: Bool = true, viewState: Bool = true, olderReports: Bool = false,
                closeIssues: [Int] = [], closeReason: String = "") {
        self.ignoredFindings = ignoredFindings
        self.viewState = viewState
        self.olderReports = olderReports
        self.closeIssues = closeIssues
        self.closeReason = closeReason
    }

    public var isEmpty: Bool { !ignoredFindings && !viewState && !olderReports && closeIssues.isEmpty }
}

/// What a reset may do with a card a survey filed. Only a card nobody has started is offered for closing:
/// cancelling work that is under way is that card's own decision, taken from its own dialog.
public enum FiledCardReset: Equatable {
    /// On the tracker and untouched — may be closed as not planned.
    case closable(issue: Int)
    /// Has a branch, or has moved past the queue. Listed with a warning, never closed from here.
    case started
    case done
    /// Only in `docs/backlog/`, with no issue to close.
    case localOnly

    public static func of(column: BoardColumn, branch: String?, issue: Int?) -> FiledCardReset {
        if column == .done { return .done }
        if branch != nil || column == .inProgress || column == .review { return .started }
        guard let issue else { return .localOnly }
        return .closable(issue: issue)
    }
}
