/// Pure: open milestones and open issues in, the roadmap out.
enum RoadmapBuilder {
    static let note = "Themes are this repository's open milestones. Work type, priority and commitment come from labels and milestone membership."

    static func build(milestones: [GitHubMilestone], issues: [GitHubIssue]) -> Roadmap {
        func key(_ milestone: GitHubMilestone, _ index: Int) -> (Int, String, String, Int) {
            let due = dueDate(milestone)
            return (due == nil ? 1 : 0, due ?? "", milestone.createdAt ?? "", index)
        }
        let ordered = milestones.enumerated().sorted { key($0.element, $0.offset) < key($1.element, $1.offset) }.map(\.element)
        var themes = ordered.map { milestone in
            RoadmapTheme(id: "milestone:\(milestone.title)", title: "Milestone · \(milestone.title)",
                         items: issues.filter { $0.milestone?.title == milestone.title && !isCritical($0) }.map { item($0, .committed) })
        }
        let unscheduled = issues.filter { $0.milestone == nil && has($0, "epic") && !isCritical($0) }
        if !unscheduled.isEmpty {
            themes.append(RoadmapTheme(id: "not-scheduled", title: "Not scheduled", items: unscheduled.map { item($0, .considered) }))
        }
        let critical = issues.filter(isCritical)
        if !critical.isEmpty {
            themes.append(RoadmapTheme(id: "critical", title: "Critical concerns", isCritical: true,
                                       items: critical.map { item($0, $0.milestone == nil ? .considered : .committed, isCritical: true) }))
        }
        return Roadmap(note: note, themes: themes, milestones: ordered.map(progress))
    }

    static func workType(_ issue: GitHubIssue) -> String {
        if has(issue, "epic") { return "Epic" }
        if has(issue, "bug") { return "Defect" }
        if has(issue, "enhancement") || has(issue, "feature") { return "Feature" }
        return "Task"
    }

    static func priority(_ issue: GitHubIssue) -> String {
        issue.labelNames.first { ["P1", "P2", "P3"].contains($0) } ?? "Unprioritised"
    }

    private static func has(_ issue: GitHubIssue, _ label: String) -> Bool {
        issue.labelNames.contains { $0.lowercased() == label }
    }

    private static func isCritical(_ issue: GitHubIssue) -> Bool {
        has(issue, "security") || has(issue, "critical")
    }

    private static func dueDate(_ milestone: GitHubMilestone) -> String? {
        milestone.dueOn.flatMap { $0.isEmpty ? nil : String($0.prefix(10)) }
    }

    private static func item(_ issue: GitHubIssue, _ commitment: Commitment, isCritical: Bool = false) -> RoadmapItem {
        RoadmapItem(id: String(issue.number), title: issue.title, workType: workType(issue), priority: priority(issue),
                    commitment: commitment, isCritical: isCritical, linkText: "Board: [#\(issue.number)](desk://task/\(issue.number))")
    }

    private static func progress(_ milestone: GitHubMilestone) -> Milestone {
        let total = milestone.openIssues + milestone.closedIssues
        let due = dueDate(milestone).map { "due \($0)" } ?? "no due date"
        return Milestone(id: milestone.title, title: milestone.title,
                         progress: total == 0 ? 0 : Double(milestone.closedIssues) / Double(total),
                         note: "\(milestone.closedIssues) of \(total) issues closed · \(due)")
    }
}
