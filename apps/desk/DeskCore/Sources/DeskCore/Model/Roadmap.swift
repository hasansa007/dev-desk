public enum Commitment: String, Hashable { case committed = "Committed", considered = "Considered" }

public struct RoadmapItem: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var workType: String     // "Epic", "Feature", "Improvement", "Defect", "Task"
    public var priority: String     // "High", "Medium", "Urgent", "P1"…
    public var commitment: Commitment
    public var isCritical: Bool
    /// Inline markdown with desk://task links, e.g. "Board: [#42](desk://task/42), [#57](desk://task/57) · Milestone 1.4".
    public var linkText: String?
    public init(id: String, title: String, workType: String, priority: String, commitment: Commitment, isCritical: Bool = false, linkText: String? = nil) {
        self.id = id
        self.title = title
        self.workType = workType
        self.priority = priority
        self.commitment = commitment
        self.isCritical = isCritical
        self.linkText = linkText
    }
}

public struct RoadmapTheme: Identifiable, Hashable {
    public var id: String
    public var title: String        // "Theme · Learning continuity", "Critical concerns"
    public var isCritical: Bool
    public var items: [RoadmapItem]

    /// The theme's glyph, chosen the way a board column chooses one, so the two screens read as one app.
    public var icon: String {
        if isCritical { return "exclamationmark.triangle" }
        return id.hasPrefix("milestone:") ? "flag" : "tray"
    }

    public init(id: String, title: String, isCritical: Bool = false, items: [RoadmapItem]) {
        self.id = id
        self.title = title
        self.isCritical = isCritical
        self.items = items
    }
}

public struct Milestone: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var progress: Double     // 0...1
    public var note: String
    /// Issue counts behind `progress`, so the Plan can say "3 of 13 done" without re-deriving it.
    public var closed: Int = 0
    public var total: Int = 0
    public init(id: String, title: String, progress: Double, note: String, closed: Int = 0, total: Int = 0) {
        self.id = id
        self.title = title
        self.progress = progress
        self.note = note
        self.closed = closed
        self.total = total
    }
}

public struct Roadmap: Hashable {
    public var note: String
    public var themes: [RoadmapTheme]
    public var milestones: [Milestone]
    public init(note: String, themes: [RoadmapTheme], milestones: [Milestone]) {
        self.note = note
        self.themes = themes
        self.milestones = milestones
    }
}
