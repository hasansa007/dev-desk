import Foundation

/// The one filter the Board and the Plan share (ADR 0046): set it on one view and it holds on the other. Search
/// stays `ProjectWindowModel.searchText`; this narrows by what an issue is, not what it says.
public struct TaskFilter: Equatable {
    /// nil = every milestone; `TaskFilter.noMilestone` = issues with none.
    public var milestone: String?
    /// "P0"…"P3", or `TaskFilter.unprioritised`.
    public var priorities: Set<String> = []
    public var kinds: Set<TaskKind> = []
    public var tags: Set<String> = []

    public static let noMilestone = "\u{0}none"
    public static let unprioritised = "none"
    public static let priorityOrder = ["P0", "P1", "P2", "P3"]
    /// The labels a card is tagged with when it carries them; the rest of a repository's labels are not filters.
    public static let tagLabels = ["security", "payments"]

    public init(milestone: String? = nil, priorities: Set<String> = [], kinds: Set<TaskKind> = [], tags: Set<String> = []) {
        self.milestone = milestone
        self.priorities = priorities
        self.kinds = kinds
        self.tags = tags
    }

    public var isActive: Bool { milestone != nil || !priorities.isEmpty || !kinds.isEmpty || !tags.isEmpty }

    /// Cards with no issue behind them — a branch, a pull request, a report — have no milestone, priority or label,
    /// so any active filter leaves them out rather than guessing.
    public func matches(_ task: DeskTask) -> Bool {
        guard isActive else { return true }
        guard task.issueNumber != nil || task.isLocalBacklog else { return false }
        if let milestone {
            if milestone == Self.noMilestone { if task.milestone != nil { return false } }
            else if task.milestone != milestone { return false }
        }
        if !priorities.isEmpty, !priorities.contains(task.priority ?? Self.unprioritised) { return false }
        if !kinds.isEmpty, !kinds.contains(task.kind) { return false }
        if !tags.isEmpty, tags.isDisjoint(with: task.labels) { return false }
        return true
    }
}

public enum TaskKind: String, CaseIterable, Hashable {
    case bug = "Bug", feature = "Feature", epic = "Epic"
}

extension DeskTask {
    /// P0–P3 from the issue's labels, the highest when more than one is set.
    public var priority: String? { TaskFilter.priorityOrder.first { labels.contains($0) } }

    /// An epic is a parent; a bug is broken behaviour; everything else (enhancement, task, ops) is work to add.
    public var kind: TaskKind {
        if labels.contains("epic") { return .epic }
        if labels.contains("bug") { return .bug }
        return .feature
    }

    /// The tag labels this card carries, in filter order.
    public var tags: [String] { TaskFilter.tagLabels.filter { labels.contains($0) } }
}

/// Work's left-pane selection (ADR 0046 decision 13).
public enum WorkScope: Hashable {
    case all
    case milestone(String)
    case noMilestone
}
