import Foundation

/// Clearing a project's survey history. A survey run appends a report; nothing has ever taken one away, so a
/// repository surveyed weekly accumulates every finding it ever had, and the screen's run picker becomes the
/// only thing standing between you and a year of them.
///
/// A reset clears the findings, so every report goes, the newest included (ADR 0041): keeping it kept every
/// finding on screen. Reports go to the Trash, the same bargain `docs/backlog/` removal makes (ADR 0027) —
/// the app's own undo is the Finder's.
public enum SurveyCleanup {
    public static let folder = "docs/survey"

    /// Every report, newest first. Only `.md` files sitting directly in `docs/survey/` count: a subfolder is
    /// somebody's own arrangement.
    public static func reports(in projectPath: String) -> [String] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let folderURL = root.appendingPathComponent(folder, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        return names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted(by: >)
    }

    /// Moves them to the Trash and returns how many went. A path that escaped `docs/survey/` is skipped rather
    /// than trusted: the names come from the folder, and this is the guard that keeps it that way.
    @discardableResult
    public static func trashReports(in projectPath: String) throws -> Int {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let folderURL = root.appendingPathComponent(folder, isDirectory: true)
        var moved = 0
        for name in reports(in: projectPath) {
            let url = folderURL.appendingPathComponent(name)
            guard SafeFile.isInside(url, folderURL) else { continue }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            moved += 1
        }
        return moved
    }
}

/// What a reset clears. Each part is owned by someone different — the app, the window, the repository, the
/// tracker — so each is asked for separately rather than one button meaning all of them.
public struct SurveyResetOptions: Equatable {
    /// Findings set aside in this project. They live in the app, never in `docs/survey/`.
    public var ignoredFindings: Bool
    /// The screen's own state: which run is selected, which filter, whether ignored ones are shown.
    public var viewState: Bool
    /// Every report in `docs/survey/`, to the Trash — the findings themselves.
    public var reports: Bool
    /// Issues the survey filed, to close as not planned with `closeReason` as the comment.
    public var closeIssues: [Int]
    public var closeReason: String
    /// `docs/backlog/` entries the survey filed, by entry id, to the Trash.
    public var trashBacklogIDs: [String]

    public init(ignoredFindings: Bool = true, viewState: Bool = true, reports: Bool = false,
                closeIssues: [Int] = [], closeReason: String = "", trashBacklogIDs: [String] = []) {
        self.ignoredFindings = ignoredFindings
        self.viewState = viewState
        self.reports = reports
        self.closeIssues = closeIssues
        self.closeReason = closeReason
        self.trashBacklogIDs = trashBacklogIDs
    }

    public var isEmpty: Bool { !ignoredFindings && !viewState && !reports && closeIssues.isEmpty && trashBacklogIDs.isEmpty }
}

/// What a reset does with a card a survey filed (ADR 0041). Work in progress is never removed from here — it is
/// kept, warned about, and offered to resume.
public enum FiledCardReset: Equatable {
    /// A GitHub issue not in progress: closed as not planned, with a reason.
    case closable(issue: Int)
    /// A `docs/backlog/` entry not in progress, Done included: its file goes to the Trash.
    case trashable(entry: String)
    /// Has a branch, or is In progress or Review.
    case inProgress
    /// An issue already Done: closed on the tracker, nothing to do.
    case done

    public static func of(column: BoardColumn, branch: String?, issue: Int?, localBacklogID: String?) -> FiledCardReset {
        if column != .done, branch != nil || column == .inProgress || column == .review { return .inProgress }
        if let localBacklogID, issue == nil { return .trashable(entry: localBacklogID) }
        if column == .done { return .done }
        guard let issue else { return .done }
        return .closable(issue: issue)
    }
}
