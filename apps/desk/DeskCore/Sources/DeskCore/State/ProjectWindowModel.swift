import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, roadmap, findings, decisions, settings
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum TaskTab: String, CaseIterable, Codable, Hashable {
    case activity, requirements, changes, evidence
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum ViewMode: String, Codable, Hashable { case focus, parallel }
public enum DockPlacement: String, Codable, Hashable { case bottom, side }
public enum DecisionsTab: String, Codable, Hashable { case needsAttention, history }

public enum SettingsSection: String, CaseIterable, Codable, Hashable {
    case general, appearance, agentsAndDefaults, accountsAndConnections, notifications, execution, projectOverrides

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .agentsAndDefaults: return "Agents and defaults"
        case .accountsAndConnections: return "Accounts and connections"
        case .notifications: return "Notifications"
        case .execution: return "Execution"
        case .projectOverrides: return "Project overrides"
        }
    }
}

public enum SheetKind: Hashable, Identifiable {
    case openProject, compareOutputs, followUp, handoff, reconcileFinding(String), cloneRepository, createProject
    case unstartedTask(String)

    public var id: String {
        switch self {
        case .openProject: return "openProject"
        case .compareOutputs: return "compareOutputs"
        case .followUp: return "followUp"
        case .handoff: return "handoff"
        case .reconcileFinding(let findingID): return "reconcileFinding:\(findingID)"
        case .cloneRepository: return "cloneRepository"
        case .createProject: return "createProject"
        case .unstartedTask(let taskID): return "unstartedTask:\(taskID)"
        }
    }
}

public enum LoadState {
    case loading
    case loaded(ProjectSnapshot)
    case failed(String)
}

@MainActor
@Observable
public final class ProjectWindowModel {
    public let ref: ProjectRef
    public let insights: InsightsConversation
    /// The doors this window has started; their shells live in `shellSessions` under the same ids.
    public let runs = DoorRuns()
    /// Each task's shell in this window. A sample has no folder, so none of its sessions can start.
    public let shellSessions: ShellSessions
    public private(set) var loadState: LoadState = .loading
    public private(set) var reloadError: String?
    public var destination: Destination = .board
    public var selectedTaskID: String?
    public private(set) var lastOpenedTaskID: String?
    public var tab: TaskTab = .activity
    public var mode: ViewMode = .focus
    public var dockOpen = true
    public var dockPlacement: DockPlacement = .bottom
    public var dockSplit = false
    public var dockTabID: String?
    public var showBacklog = false
    public var searchText = ""
    public var insightsOpen = false
    public var insightsDocked = false
    public var runsOpen = false
    public var runsDocked = false
    public var sheet: SheetKind?
    public var decisionsTab: DecisionsTab = .needsAttention
    public var selectedDecisionID: String?
    public var selectedFindingID: String?
    public var selectedRunID: String?
    public var findingFilter: FindingCategory?
    public var settingsSection: SettingsSection = .agentsAndDefaults
    public private(set) var answeredDecisionID: String?

    @ObservationIgnored private let source: ProjectDataSource
    @ObservationIgnored private var isLoading = false

    public init(ref: ProjectRef, source: ProjectDataSource, insightsDelay: Duration = .milliseconds(900)) {
        self.ref = ref
        self.source = source
        self.insights = InsightsConversation(delay: insightsDelay)
        if case .local(let path) = ref {
            shellSessions = ShellSessions(projectRoot: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            shellSessions = ShellSessions(projectRoot: nil)
        }
    }

    public var snapshot: ProjectSnapshot? {
        if case .loaded(let snapshot) = loadState { return snapshot }
        return nil
    }

    public var tasks: [DeskTask] { snapshot?.board.value ?? [] }
    public var selectedTask: DeskTask? { selectedTaskID.flatMap(task) }
    public func task(_ id: String) -> DeskTask? { tasks.first { $0.id == id } }
    public var openTaskCount: Int { tasks.filter { $0.column != .done }.count }
    public var findingsCount: Int? { snapshot?.findings.value?.findings.count }
    public var pendingDecisionCount: Int { (snapshot?.decisions.value ?? []).filter { $0.state == .needsAttention }.count }
    public var parallelTasks: [DeskTask] { Array(tasks.filter { $0.column == .inProgress && !$0.parallel.isNone }.prefix(4)) }

    /// Loads or reloads the snapshot; the launch selection applies only to the first load. A call made while one runs, or a cancelled load, changes nothing.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let isFirstLoad = snapshot == nil
        do {
            let loaded = try await source.load()
            guard !Task.isCancelled else { return }
            loadState = .loaded(loaded)
            reloadError = nil
            guard isFirstLoad else { return }
            insights.configure(loaded.insights)
            selectedTaskID = loaded.launch.selectedTaskID
            lastOpenedTaskID = loaded.launch.selectedTaskID
            insightsOpen = loaded.launch.insightsOpen
            selectedRunID = loaded.findings.value?.runs.first?.id
            selectedFindingID = loaded.findings.value?.findings.first?.id
            selectedDecisionID = loaded.decisions.value?.first { $0.state != .answered }?.id
        } catch {
            guard !Task.isCancelled else { return }
            if isFirstLoad { loadState = .failed(error.localizedDescription) } else { reloadError = error.localizedDescription }
        }
    }

    public func go(_ destination: Destination) {
        self.destination = destination
        if destination == .board {
            selectedTaskID = nil
            mode = .focus
        }
    }

    /// An unstarted card opens as a sheet over the board; anything with work behind it opens its workspace.
    public func openTask(_ id: String) {
        destination = .board
        lastOpenedTaskID = id
        guard task(id)?.isUnstarted != true else {
            sheet = .unstartedTask(id)
            return
        }
        mode = .focus
        selectedTaskID = id
        tab = .activity
        dockTabID = nil
    }

    public func setMode(_ mode: ViewMode) {
        self.mode = mode
        destination = .board
    }

    /// Runs the selected task's next action; returns a URL only when the view must open it.
    public func performNextAction() -> URL? {
        guard let action = selectedTask?.nextAction else { return nil }
        switch action {
        case .reviewChanges: tab = .changes
        case .answerDecision(let decisionID): openDecision(decisionID)
        case .startHandoff: sheet = .handoff
        case .openURL(let url, _): return url
        }
        return nil
    }

    public func openDecision(_ id: String?) {
        destination = .decisions
        decisionsTab = .needsAttention
        mode = .focus
        if let id { selectedDecisionID = id }
    }

    public func openFinding(_ id: String) {
        destination = .findings
        findingFilter = nil
        selectedFindingID = id
    }

    public func handle(_ link: DeskLink) {
        switch link {
        case .task(let id): openTask(id)
        case .finding(let id): openFinding(id)
        case .decision(let id): openDecision(id)
        }
    }

    public func toggleDock() { dockOpen.toggle() }

    public func setDockPlacement(_ placement: DockPlacement) {
        dockPlacement = placement
        dockOpen = true
    }

    public func toggleSplit() { dockSplit.toggle() }

    /// Routes an agent row's button; Stop and Continue only leave a demo note, since nothing runs.
    public func perform(_ action: AgentAction, agentID: String) {
        guard let task = selectedTask else { return }
        switch action {
        case .openTerminal:
            dockOpen = true
            dockTabID = task.dock?.tabs.first?.id
        case .viewActivity:
            dockOpen = true
            dockSplit = true
        case .requestFollowUp:
            sheet = .followUp
        case .readResult:
            tab = .evidence
        case .stop, .continueSession:
            let name = task.agents.first { $0.id == agentID }?.name ?? "the agent"
            let verb = action == .stop ? "Stop" : "Continue"
            appendDemoEvent(taskID: task.id, text: "\(verb) requested for \(name) (demo). No process was touched.")
        }
    }

    public func present(_ sheet: SheetKind) { self.sheet = sheet }
    public func dismissSheet() { sheet = nil }

    /// Confirms a demo sheet by recording it on the task; nothing leaves the app.
    public func confirmSheet(provider: String? = nil) {
        defer { self.sheet = nil }
        guard let current = sheet else { return }
        if case .reconcileFinding(let findingID) = current {
            markReconciled(findingID)
            return
        }
        guard let taskID = selectedTaskID ?? lastOpenedTaskID else { return }
        switch current {
        case .compareOutputs:
            appendDemoEvent(taskID: taskID, text: "Adopted the Codex result for the compared criterion (demo).")
        case .followUp:
            appendDemoEvent(taskID: taskID, text: "Follow-up request sent to the coordinating agent (demo).")
        case .handoff:
            appendDemoEvent(taskID: taskID, text: "New \(provider ?? "Codex") session created from a handoff (demo). The existing checkout was not changed.")
        default:
            break
        }
    }

    public func toggleInsights() { insightsOpen.toggle() }

    public func dockInsights() {
        insightsDocked = true
        insightsOpen = true
    }

    public func toggleRuns() { runsOpen.toggle() }

    public func dockRuns() {
        runsDocked = true
        runsOpen = true
    }

    public func floatRuns() {
        runsDocked = false
        runsOpen = true
    }

    public func floatInsights() {
        insightsDocked = false
        insightsOpen = true
    }

    /// Demo only: records the answer and moves the waiting task back to running.
    public func recordAnswer(decisionID: String, optionID: String?, rationale: String) {
        guard snapshot?.isDemo == true else { return }
        mutateDemoSnapshot { snapshot in
            guard var decisions = snapshot.decisions.value,
                  let index = decisions.firstIndex(where: { $0.id == decisionID }) else { return }
            let option = decisions[index].options.first { $0.id == optionID }
            decisions[index].state = .answered
            decisions[index].answer = DecisionAnswer(optionTitle: option?.title, rationale: rationale, answeredLabel: "Answered just now")
            snapshot.decisions = .available(decisions)
            guard var tasks = snapshot.board.value else { return }
            for i in tasks.indices where tasks[i].nextAction == .answerDecision(decisionID: decisionID) {
                tasks[i].headerBadge = StatusBadge(.running, "Running", pulses: true)
                tasks[i].cardBadge = StatusBadge(.running, "Running", pulses: true)
                tasks[i].cardNote = "Session resumed with your answer"
                tasks[i].notice = nil
                tasks[i].nextAction = nil
            }
            snapshot.board = .available(tasks)
        }
        answeredDecisionID = decisionID
    }

    public func requestMoreEvidence(decisionID: String) {
        guard let taskID = snapshot?.decisions.value?.first(where: { $0.id == decisionID })?.taskID else { return }
        appendDemoEvent(taskID: taskID, text: "Asked the session for more evidence (demo).")
    }

    private func markReconciled(_ findingID: String) {
        mutateDemoSnapshot { snapshot in
            guard var report = snapshot.findings.value,
                  let index = report.findings.firstIndex(where: { $0.id == findingID }) else { return }
            report.findings[index].reconcile?.queuedNote = "Update queued locally (demo). Nothing was sent to the tracker."
            snapshot.findings = .available(report)
        }
    }

    private func appendDemoEvent(taskID: String, text: String) {
        mutateDemoSnapshot { snapshot in
            guard var tasks = snapshot.board.value,
                  let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            var events = tasks[index].activity.value ?? []
            events.insert(ActivityEvent(id: UUID().uuidString, time: Self.clock.string(from: Date()), text: text), at: 0)
            tasks[index].activity = .available(events)
            snapshot.board = .available(tasks)
        }
    }

    private func mutateDemoSnapshot(_ change: (inout ProjectSnapshot) -> Void) {
        guard var current = self.snapshot, current.isDemo else { return }
        change(&current)
        loadState = .loaded(current)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
