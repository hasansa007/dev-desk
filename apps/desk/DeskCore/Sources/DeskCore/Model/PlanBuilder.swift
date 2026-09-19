import Foundation

/// One row of the Plan (ADR 0046): a milestone, how far along it is, how urgent its open work is, and that work.
public struct PlanRow: Identifiable, Equatable {
    public var id: String { title ?? PlanRow.noMilestoneID }
    /// nil for the final "No milestone" row.
    public var title: String?
    public var closed: Int
    public var total: Int
    public var isWorkingNow: Bool
    /// Open issues, highest priority first, as the Board's cards (so filters and states agree).
    public var tasks: [DeskTask]
    public static let noMilestoneID = "\u{0}no-milestone"

    /// P0…P3 counts over the row's open issues, zero counts left out.
    public var priorityCounts: [(priority: String, count: Int)] {
        TaskFilter.priorityOrder.compactMap { p in
            let n = tasks.filter { $0.priority == p }.count
            return n > 0 ? (p, n) : nil
        }
    }

    public static func == (a: PlanRow, b: PlanRow) -> Bool {
        a.title == b.title && a.closed == b.closed && a.total == b.total && a.isWorkingNow == b.isWorkingNow
            && a.tasks.map(\.id) == b.tasks.map(\.id)
    }
}

public enum PlanBuilder {
    /// Rows in the Plan's order (the stored order, then the roadmap's), the working milestone marked, and a final
    /// "No milestone" row for open issues filed nowhere. `filter` narrows the tasks; a row it empties is left out,
    /// unless no filter is set — an empty milestone is still part of the plan.
    public static func rows(milestones: [Milestone], order: PlanOrder, active: String?, tasks: [DeskTask],
                            filter: TaskFilter = TaskFilter(), matches: (DeskTask) -> Bool = { _ in true }) -> [PlanRow] {
        let open = tasks.filter { ($0.issueNumber != nil || $0.isLocalBacklog) && $0.column != .done }
        let visible = open.filter { filter.matches($0) && matches($0) }
        func sorted(_ items: [DeskTask]) -> [DeskTask] {
            items.sorted { (rank($0), $0.issueNumber ?? .max) < (rank($1), $1.issueNumber ?? .max) }
        }
        var rows = order.apply(milestones, title: \.title).map { m in
            PlanRow(title: m.title, closed: m.closed, total: m.total, isWorkingNow: m.title == active,
                    tasks: sorted(visible.filter { $0.milestone == m.title }))
        }
        let unplaced = sorted(visible.filter { $0.milestone == nil })
        rows.append(PlanRow(title: nil, closed: 0, total: unplaced.count, isWorkingNow: false, tasks: unplaced))
        let narrowed = filter.isActive || visible.count != open.count
        return rows.filter { !$0.tasks.isEmpty || ($0.title != nil && !narrowed) }
    }

    private static func rank(_ task: DeskTask) -> Int {
        task.priority.flatMap { TaskFilter.priorityOrder.firstIndex(of: $0) } ?? TaskFilter.priorityOrder.count
    }
}
