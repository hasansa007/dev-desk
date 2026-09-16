import Foundation

/// Clearing a project's findings history. A findings run appends a report; nothing has ever taken one away, so a
/// repository checked weekly accumulates every finding it ever had, and the screen's run picker becomes the
/// only thing standing between you and a year of them.
///
/// A reset clears the findings, so every report goes, the newest included (ADR 0041): keeping it kept every
/// finding on screen. Reports go to the Trash, the same bargain `docs/backlog/` removal makes (ADR 0027) —
/// the app's own undo is the Finder's.
public enum FindingsCleanup {
    public static let folder = "docs/findings"
    /// Where reports were written before the door was renamed from `dev:survey` (ADR 0042). Still read and still
    /// cleared, so a project checked before the rename keeps its findings and loses them only to a reset.
    public static let legacyFolder = "docs/survey"
    public static let folders = [folder, legacyFolder]

    /// Every report, newest first. Only `.md` files sitting directly in a reports folder count: a subfolder is
    /// somebody's own arrangement.
    public static func reports(in projectPath: String) -> [String] {
        reportFiles(in: projectPath).map(\.name)
    }

    /// Moves them to the Trash and returns how many went. A path that escaped its folder is skipped rather
    /// than trusted: the names come from the folder, and this is the guard that keeps it that way.
    @discardableResult
    public static func trashReports(in projectPath: String) throws -> Int {
        var moved = 0
        for file in reportFiles(in: projectPath) {
            guard SafeFile.isInside(file.url, file.folder) else { continue }
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            moved += 1
        }
        return moved
    }

    private static func reportFiles(in projectPath: String) -> [(name: String, url: URL, folder: URL)] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        return folders.flatMap { relative -> [(name: String, url: URL, folder: URL)] in
            let folderURL = root.appendingPathComponent(relative, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? []
            return names.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
                .map { ($0, folderURL.appendingPathComponent($0), folderURL) }
        }
        .sorted { $0.name > $1.name }
    }
}

/// What a reset clears. Each part is owned by someone different — the app, the window, the repository, the
/// tracker — so each is asked for separately rather than one button meaning all of them.
public struct FindingsResetOptions: Equatable {
    /// Findings set aside in this project. They live in the app, never in a reports folder.
    public var ignoredFindings: Bool
    /// The screen's own state: which run is selected, which filter, whether ignored ones are shown.
    public var viewState: Bool
    /// Every report in `docs/findings/` (and the older `docs/survey/`), to the Trash — the findings themselves.
    public var reports: Bool
    /// Issues the findings run filed, to close as not planned with `closeReason` as the comment.
    public var closeIssues: [Int]
    public var closeReason: String
    /// `docs/backlog/` entries the findings run filed, by entry id, to the Trash.
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

/// What a reset does with a card a findings run filed (ADR 0041). Work in progress is never removed from here — it is
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
