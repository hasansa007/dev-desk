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
    public var insightsOpen: Bool

    public init(selectedTaskID: String? = nil, insightsOpen: Bool = false) {
        self.selectedTaskID = selectedTaskID
        self.insightsOpen = insightsOpen
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
    public var roadmap: Surface<Roadmap>
    public var decisions: Surface<[Decision]>
    public var connections: [Connection]
    public var connectionsNote: String
    public var capabilities: CapabilityMatrix
    public var insights: InsightsAvailability
    /// Settings › Project overrides: base branch, remote and similar read-only facts.
    public var projectFacts: [KeyValue]

    public init(project: ProjectInfo, isDemo: Bool, launch: LaunchState = LaunchState(),
                activitySummary: StatusBadge? = nil, board: Surface<[DeskTask]>, boardNote: String,
                findings: Surface<FindingsReport>, roadmap: Surface<Roadmap>, decisions: Surface<[Decision]>,
                connections: [Connection], connectionsNote: String, capabilities: CapabilityMatrix,
                insights: InsightsAvailability, projectFacts: [KeyValue] = []) {
        self.project = project
        self.isDemo = isDemo
        self.launch = launch
        self.activitySummary = activitySummary
        self.board = board
        self.boardNote = boardNote
        self.findings = findings
        self.roadmap = roadmap
        self.decisions = decisions
        self.connections = connections
        self.connectionsNote = connectionsNote
        self.capabilities = capabilities
        self.insights = insights
        self.projectFacts = projectFacts
    }
}
