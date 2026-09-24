import Foundation

/// Declaration order is the on-screen column order: the board renders `allCases` left to right.
public enum BoardColumn: String, CaseIterable, Codable, Hashable {
    case backlog, readyForDev, queued, inProgress, review, done

    public var title: String {
        switch self {
        case .backlog: return "Backlog"
        // "Next up" (ADR 0046): the working milestone plus moves made here — what "Ready for dev" meant, said plainly.
        case .readyForDev: return "Next up"
        case .queued: return "Queued"
        case .inProgress: return "In progress"
        case .review: return "Review"
        case .done: return "Done"
        }
    }

    /// The column's own glyph, so a header is recognisable before it is read.
    public var icon: String {
        switch self {
        case .backlog: return "tray"
        case .readyForDev: return "checklist"
        // An hourglass, not a calendar: Queued means "waiting for a free agent slot" now (ADR 0035),
        // not membership of the active milestone.
        case .queued: return "hourglass"
        case .inProgress: return "play.circle"
        case .review: return "eye"
        case .done: return "checkmark.circle"
        }
    }
}

public enum NextAction: Hashable {
    case reviewChanges
    case answerDecision
    case startHandoff
    case openURL(URL, title: String)

    public var title: String {
        switch self {
        case .reviewChanges: return "Review changes"
        case .answerDecision: return "Answer decision"
        case .startHandoff: return "Start with handoff…"
        case .openURL(_, let title): return title
        }
    }
}

public struct ConnectionLevel: Hashable {
    public var name: String
    public var isAvailable: Bool
    public var statusLabel: String
    public var detail: String
    public init(name: String, isAvailable: Bool, statusLabel: String, detail: String) {
        self.name = name
        self.isAvailable = isAvailable
        self.statusLabel = statusLabel
        self.detail = detail
    }
}

public struct ExternalConnection: Hashable {
    public var title: String
    /// Inline markdown; code spans render monospaced.
    public var message: String
    public var levels: [ConnectionLevel]
    public var facts: [KeyValue]
    public var handoffNote: String
    public var checkoutPath: String
    public init(title: String, message: String, levels: [ConnectionLevel], facts: [KeyValue], handoffNote: String, checkoutPath: String) {
        self.title = title
        self.message = message
        self.levels = levels
        self.facts = facts
        self.handoffNote = handoffNote
        self.checkoutPath = checkoutPath
    }
}

public enum TaskNotice: Hashable {
    case waitingForDecision(title: String, message: String, decisionID: String)
    case externalConnection(ExternalConnection)
}

public enum StageState: String, Hashable { case done, current, pending }

public struct PipelineStage: Hashable {
    public var name: String
    public var state: StageState
    public init(_ name: String, _ state: StageState) { self.name = name; self.state = state }
}

public struct PipelineProgress: Hashable {
    public var stages: [PipelineStage]
    public var note: String?
    public init(stages: [PipelineStage], note: String? = nil) { self.stages = stages; self.note = note }
}

public struct ToolDetail: Hashable {
    public var title: String
    public var lines: [String]
    public init(title: String, lines: [String]) { self.title = title; self.lines = lines }
}

public struct ActivityEvent: Identifiable, Hashable {
    public var id: String
    public var time: String
    /// Inline markdown: **bold** actor names, `code` paths, [links](desk://…).
    public var text: String
    public var detail: ToolDetail?
    public var offersFollowUp: Bool
    public init(id: String, time: String, text: String, detail: ToolDetail? = nil, offersFollowUp: Bool = false) {
        self.id = id
        self.time = time
        self.text = text
        self.detail = detail
        self.offersFollowUp = offersFollowUp
    }
}

public struct AcceptanceCriterion: Hashable {
    public var text: String
    public var isMet: Bool
    public init(_ text: String, isMet: Bool) { self.text = text; self.isMet = isMet }
}

public struct Requirements: Hashable {
    public var goal: String
    public var criteria: [AcceptanceCriterion]
    public var outOfScope: String?
    public var sources: String?
    /// Full issue description for real projects; nil for the sample.
    public var body: String?
    public init(goal: String, criteria: [AcceptanceCriterion] = [], outOfScope: String? = nil, sources: String? = nil, body: String? = nil) {
        self.goal = goal
        self.criteria = criteria
        self.outOfScope = outOfScope
        self.sources = sources
        self.body = body
    }
}

public struct ChangedFile: Identifiable, Hashable {
    public var id: String            // full repository path
    public var displayPath: String   // shortened path shown in the list
    public var additions: Int?       // nil = binary
    public var deletions: Int?
    public init(id: String, displayPath: String, additions: Int?, deletions: Int?) {
        self.id = id
        self.displayPath = displayPath
        self.additions = additions
        self.deletions = deletions
    }
}

public struct DiffLine: Hashable {
    public enum Kind: String, Hashable { case context, addition, deletion }
    public var kind: Kind
    /// Without the leading " ", "+" or "-"; the viewer adds "  ", "+ " or "- ".
    public var text: String
    public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
}

public struct DiffHunk: Hashable {
    public var header: String
    public var lines: [DiffLine]
    public init(header: String, lines: [DiffLine]) { self.header = header; self.lines = lines }
}

public struct FileDiff: Hashable {
    public var path: String
    public var hunks: [DiffHunk]
    public var truncated: Bool
    public init(path: String, hunks: [DiffHunk], truncated: Bool = false) {
        self.path = path
        self.hunks = hunks
        self.truncated = truncated
    }
}

public struct ChangeSet: Hashable {
    public var files: [ChangedFile]
    /// Inline markdown, e.g. "Diff is against `main` at `9c2e410`. Demo content."
    public var baseNote: String
    /// Keyed by ChangedFile.id; a missing key means no preview is available for that file.
    public var diffs: [String: FileDiff]
    public init(files: [ChangedFile], baseNote: String, diffs: [String: FileDiff] = [:]) {
        self.files = files
        self.baseNote = baseNote
        self.diffs = diffs
    }
}

public enum CheckOutcome: String, Hashable { case passed, warning, failed }

public struct CheckResult: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var outcome: CheckOutcome
    public var outcomeLabel: String
    public var revisionLabel: String
    public init(id: String, name: String, outcome: CheckOutcome, outcomeLabel: String, revisionLabel: String) {
        self.id = id
        self.name = name
        self.outcome = outcome
        self.outcomeLabel = outcomeLabel
        self.revisionLabel = revisionLabel
    }
}

public struct FailedRun: Hashable {
    public var title: String
    public var message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
}

public struct LinkedEvidence: Hashable {
    public var title: String
    public var badge: String
    public var findingID: String?
    public init(title: String, badge: String, findingID: String?) {
        self.title = title
        self.badge = badge
        self.findingID = findingID
    }
}

public struct Evidence: Hashable {
    public var isDemo: Bool
    public var checks: [CheckResult]
    public var failure: FailedRun?
    public var limitations: String?
    public var linked: [LinkedEvidence]
    public init(isDemo: Bool, checks: [CheckResult] = [], failure: FailedRun? = nil, limitations: String? = nil, linked: [LinkedEvidence] = []) {
        self.isDemo = isDemo
        self.checks = checks
        self.failure = failure
        self.limitations = limitations
        self.linked = linked
    }
}

public struct Dependency: Hashable {
    /// Inline markdown with desk:// links, e.g. "Blocked by [#59](desk://task/59) — …".
    public var text: String
    public var taskID: String?
    public init(text: String, taskID: String?) { self.text = text; self.taskID = taskID }
}

public struct TerminalLine: Hashable {
    public enum Kind: String, Hashable { case plain, success, failure, dim }
    public var kind: Kind
    public var text: String
    public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
}

public struct TerminalTranscript: Hashable {
    public var header: String
    public var lines: [TerminalLine]
    public var showsPrompt: Bool
    public var isReadOnly: Bool
    public init(header: String, lines: [TerminalLine], showsPrompt: Bool = true, isReadOnly: Bool = false) {
        self.header = header
        self.lines = lines
        self.showsPrompt = showsPrompt
        self.isReadOnly = isReadOnly
    }
}

public enum ParallelPreview: Hashable {
    case transcript(TerminalTranscript)
    case decision(title: String, question: String, decisionID: String, note: String)
    case activity([ActivityEvent])
    case none(String)

    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}

public struct ComparedOutput: Hashable {
    public var title: String
    public var stateLabel: String
    public var tone: StatusTone
    public var summaryLines: [String]
    public var result: String
    public init(title: String, stateLabel: String, tone: StatusTone, summaryLines: [String], result: String) {
        self.title = title
        self.stateLabel = stateLabel
        self.tone = tone
        self.summaryLines = summaryLines
        self.result = result
    }
}

public struct OutputComparison: Hashable {
    public var intro: String
    public var left: ComparedOutput
    public var right: ComparedOutput
    public var footnote: String
    public var confirmTitle: String
    public init(intro: String, left: ComparedOutput, right: ComparedOutput, footnote: String, confirmTitle: String) {
        self.intro = intro
        self.left = left
        self.right = right
        self.footnote = footnote
        self.confirmTitle = confirmTitle
    }
}

public struct FollowUpDraft: Hashable {
    public var explanation: String
    public var reviewerNote: String
    public var request: String
    public var recipient: String
    public init(explanation: String, reviewerNote: String, request: String, recipient: String) {
        self.explanation = explanation
        self.reviewerNote = reviewerNote
        self.request = request
        self.recipient = recipient
    }
}

public struct HandoffPlan: Hashable {
    /// Inline markdown; "**new session**" is bold.
    public var warning: String
    public var rows: [KeyValue]
    public var providers: [String]
    public var footnote: String
    public init(warning: String, rows: [KeyValue], providers: [String], footnote: String) {
        self.warning = warning
        self.rows = rows
        self.providers = providers
        self.footnote = footnote
    }
}

public struct DeskTask: Identifiable, Hashable {
    public var id: String
    public var issueNumber: Int?
    public var title: String
    public var column: BoardColumn
    /// Monospaced suffix after the issue label ("merged", "feat/run-summary"); shown alone when there is no issue.
    public var cardMeta: String?
    public var cardBadge: StatusBadge?
    /// Plain text beside the issue label, e.g. "No agent assigned".
    public var cardInlineText: String?
    public var cardNote: String?
    public var cardNoteIsWarning: Bool
    public var isDimmed: Bool
    public var headerBadge: StatusBadge
    public var branchLine: String
    public var parallelLine: String
    /// The task's git branch when one is known; nil for an issue nobody has branched yet, and for samples.
    public var branch: String?
    /// Why the task has no branch to open when it isn't that nobody has branched yet, such as a pull request from a fork.
    public var noBranchNote: String?
    /// The ref a detached agent worktree starts from, e.g. "refs/remotes/origin/main"; nil for samples.
    public var baseRef: String?
    /// What `baseRef` pointed at when the board was built, short — the half a `TaskLaunch` pins so two runs
    /// of one launch cannot silently sit on different code (ADR 0036).
    public var baseShort: String?
    public var nextAction: NextAction?
    public var notice: TaskNotice?
    public var pipeline: PipelineProgress?
    public var activity: Surface<[ActivityEvent]>
    public var canCompareOutputs: Bool
    public var requirements: Surface<Requirements>
    public var changes: Surface<ChangeSet>
    public var evidence: Surface<Evidence>
    public var dependencies: [Dependency]
    public var parallel: ParallelPreview
    public var comparison: OutputComparison?
    public var followUp: FollowUpDraft?
    public var handoff: HandoffPlan?
    /// "High", "Medium" or "Low" from the issue's `impact:` label; nil when nobody has rated it (ADR 0020).
    public var impact: String?
    public var complexity: String?
    /// The issue's labels and milestone, so a filter can narrow the board without reading GitHub again (ADR 0046).
    public var labels: [String] = []
    public var milestone: String? = nil
    /// The code the issue says it changes (`touches:` in its body), for Start's overlap check (ADR 0046).
    public var touches: [CodeTouch] = []
    /// When this task's branch was last committed to; nil for a card with no branch. What tells a finished
    /// branch from live work, since git's In Progress rule cannot.
    public var lastCommit: Date?
    /// Commits this branch holds that the base does not, so a delete can say what would be lost.
    public var unmergedCount: Int?
    /// The open pull request behind this card when one is known — what the Review card's backwards move
    /// converts to a draft. Nil for a card with no pull request, and for samples.
    public var pullRequestNumber: Int?
    /// A branch whose commits are only a door's report: in Review until approved, which merges it, then Done.
    public var isFinishedReport: Bool = false
    /// A Done card's leftover worktree: its branch is merged and still checked out in a folder of its own.
    public var worktreePath: String?
    /// The worktree this card's branch is checked out in, whatever its column; nil when it is checked out nowhere
    /// but the opened folder. What lets a run started for one card be found working on this one's branch.
    public var checkoutPath: String?

    /// A local branch with no issue and no pull request behind it — the only card whose branch this app may delete.
    public var isBranchCard: Bool { id.hasPrefix("branch:") }

    /// A merged pull request card, or a done card the tracker marked merged — history, never startable.
    public var isMerged: Bool { id.hasPrefix("merged:") || (column == .done && cardMeta == "merged") }

    public static let localPrefix = "local:"
    /// Work recorded in `docs/backlog/` rather than in a tracker (ADR 0027).
    public var isLocalBacklog: Bool { id.hasPrefix(Self.localPrefix) }
    /// The entry's file stem, for the card that has to find its file again.
    public var localBacklogID: String? { isLocalBacklog ? String(id.dropFirst(Self.localPrefix.count)) : nil }

    /// The value of a `kind:value` label, capitalised: `impact:high` becomes "High".
    public static func rating(_ kind: String, in labels: [String]) -> String? {
        guard let label = labels.first(where: { $0.lowercased().hasPrefix("\(kind):") }) else { return nil }
        let value = label.dropFirst(kind.count + 1).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value.prefix(1).uppercased() + value.dropFirst().lowercased()
    }

    public var issueLabel: String { issueNumber.map { "#\($0)" } ?? "" }

    /// Nobody has started this: no branch of its own, and still before the columns git owns. A pull request
    /// from a fork also has no branch here, but it is in Review, so it keeps its workspace.
    public var isUnstarted: Bool { branch == nil && (column == .backlog || column == .readyForDev || column == .queued) }

    /// What the task's shell and `/dev` call it: the issue number, else the N of a gh-N-… branch.
    public var taskNumber: Int? { issueNumber ?? branch.flatMap { Self.ghNumber($0) } }

    /// The N of a branch named gh-N-…, the form /dev cuts.
    static func ghNumber(_ branch: String) -> Int? {
        guard branch.hasPrefix("gh-") else { return nil }
        let rest = branch.dropFirst(3)
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix("-") else { return nil }
        return Int(digits)
    }

    public init(id: String, issueNumber: Int? = nil, title: String, column: BoardColumn,
                cardMeta: String? = nil, cardBadge: StatusBadge? = nil, cardInlineText: String? = nil,
                cardNote: String? = nil, cardNoteIsWarning: Bool = false, isDimmed: Bool = false,
                headerBadge: StatusBadge, branchLine: String, parallelLine: String = "", branch: String? = nil, noBranchNote: String? = nil,
                baseRef: String? = nil, nextAction: NextAction? = nil, notice: TaskNotice? = nil, pipeline: PipelineProgress? = nil,
                activity: Surface<[ActivityEvent]> = .available([]), canCompareOutputs: Bool = false,
                requirements: Surface<Requirements>, changes: Surface<ChangeSet>, evidence: Surface<Evidence>,
                dependencies: [Dependency] = [],
                parallel: ParallelPreview, comparison: OutputComparison? = nil,
                followUp: FollowUpDraft? = nil, handoff: HandoffPlan? = nil,
                impact: String? = nil, complexity: String? = nil, lastCommit: Date? = nil, unmergedCount: Int? = nil,
                pullRequestNumber: Int? = nil) {
        self.impact = impact
        self.lastCommit = lastCommit
        self.unmergedCount = unmergedCount
        self.pullRequestNumber = pullRequestNumber
        self.complexity = complexity
        self.id = id
        self.issueNumber = issueNumber
        self.title = title
        self.column = column
        self.cardMeta = cardMeta
        self.cardBadge = cardBadge
        self.cardInlineText = cardInlineText
        self.cardNote = cardNote
        self.cardNoteIsWarning = cardNoteIsWarning
        self.isDimmed = isDimmed
        self.headerBadge = headerBadge
        self.branchLine = branchLine
        self.parallelLine = parallelLine
        self.branch = branch
        self.noBranchNote = noBranchNote
        self.baseRef = baseRef
        self.nextAction = nextAction
        self.notice = notice
        self.pipeline = pipeline
        self.activity = activity
        self.canCompareOutputs = canCompareOutputs
        self.requirements = requirements
        self.changes = changes
        self.evidence = evidence
        self.dependencies = dependencies
        self.parallel = parallel
        self.comparison = comparison
        self.followUp = followUp
        self.handoff = handoff
    }
}
