public struct ProjectInfo: Hashable {
    public var name: String
    public var displayPath: String
    public var branch: String
    public var remote: String?
    public var headRevision: String?

    public init(name: String, displayPath: String, branch: String, remote: String? = nil, headRevision: String? = nil) {
        self.name = name
        self.displayPath = displayPath
        self.branch = branch
        self.remote = remote
        self.headRevision = headRevision
    }
}

/// What a freshly opened window selects before any restored layout is applied.
public struct LaunchState: Hashable {
    public var selectedTaskID: String?

    public init(selectedTaskID: String? = nil) {
        self.selectedTaskID = selectedTaskID
    }
}

public struct ProjectSnapshot: Hashable {
    public var project: ProjectInfo
    public var isDemo: Bool
    public var launch: LaunchState
    public var activitySummary: StatusBadge?
    public var board: Surface<[DeskTask]>
    public var boardNote: String
    public var findings: Surface<FindingsReport>
    /// `docs/ideation/` reports; an empty one reads as "no runs yet", which is not the same as unavailable.
    public var ideation: Surface<IdeationReport>
    public var roadmap: Surface<Roadmap>
    public var connections: [Connection]
    public var connectionsNote: String
    public var capabilities: CapabilityMatrix
    public var insights: InsightsAvailability
    /// Settings › Project overrides: base branch, remote and similar read-only facts.
    public var projectFacts: [KeyValue]
    /// `owner/repo`, for writes that must name the repository; nil when there is no GitHub remote to write to.
    public var slug: String?
    /// The milestone that decides the Queued column, so a card can be moved into or out of it.
    public var activeMilestone: String?
    /// Work recorded in `docs/backlog/` while there was no tracker to file into (ADR 0027).
    public var localBacklog: [BacklogItem] = []
    /// Keys of local entries that have since become issues, so what filed them never offers to file them again.
    public var filedBacklogKeys: Set<String> = []
    /// The repository's top level, where `docs/backlog/` is read from — so a write lands in the folder the board
    /// reads, even when the window was opened on a subfolder. Nil for a sample or a folder that is not a repo.
    public var repositoryRoot: String?

    public init(project: ProjectInfo, isDemo: Bool, launch: LaunchState = LaunchState(),
                activitySummary: StatusBadge? = nil, board: Surface<[DeskTask]>, boardNote: String,
                findings: Surface<FindingsReport>, ideation: Surface<IdeationReport> = .available(IdeationReport()),
                roadmap: Surface<Roadmap>,
                connections: [Connection], connectionsNote: String, capabilities: CapabilityMatrix,
                insights: InsightsAvailability, projectFacts: [KeyValue] = [],
                slug: String? = nil, activeMilestone: String? = nil,
                localBacklog: [BacklogItem] = [], filedBacklogKeys: Set<String> = [], repositoryRoot: String? = nil) {
        self.repositoryRoot = repositoryRoot
        self.localBacklog = localBacklog
        self.filedBacklogKeys = filedBacklogKeys
        self.ideation = ideation
        self.project = project
        self.isDemo = isDemo
        self.launch = launch
        self.activitySummary = activitySummary
        self.board = board
        self.boardNote = boardNote
        self.findings = findings
        self.roadmap = roadmap
        self.connections = connections
        self.connectionsNote = connectionsNote
        self.capabilities = capabilities
        self.insights = insights
        self.projectFacts = projectFacts
        self.slug = slug
        self.activeMilestone = activeMilestone
    }
}
