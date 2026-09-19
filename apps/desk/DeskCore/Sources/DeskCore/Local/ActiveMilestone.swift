/// dev.py's resolve_active_milestone: the open milestone due soonest, else the oldest open one; a same-day tie is never broken silently.
/// The Plan's stored order (ADR 0046) comes first when there is one: its top open milestone is "Working now".
enum ActiveMilestone {
    static func resolve(_ milestones: [GitHubMilestone], order: [String] = []) -> (title: String?, why: String) {
        let open = Set(milestones.map(\.title))
        if let top = order.first(where: open.contains) { return (top, "top of Plan") }
        let dated = milestones.enumerated()
            .compactMap { index, milestone in milestone.dueOn.flatMap { $0.isEmpty ? nil : (due: $0, index: index, title: milestone.title) } }
            .sorted { ($0.due, $0.index) < ($1.due, $1.index) }
        if let first = dated.first {
            let day = String(first.due.prefix(10))
            if dated.count > 1, dated[1].due.prefix(10) == day {
                return (nil, "\(first.title) and \(dated[1].title) are due the same day")
            }
            return (first.title, "nearest due date \(day)")
        }
        guard let oldest = milestones.min(by: { ($0.createdAt ?? "") < ($1.createdAt ?? "") }) else {
            return (nil, "no open milestone")
        }
        return (oldest.title, "oldest open milestone; none has a due date")
    }
}
