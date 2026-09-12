import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, roadmap, survey, ideation, decisions, settings
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
    case task(String)
    case cancelTask(String)
    case runFocus(String)

    public var id: String {
        switch self {
        case .openProject: return "openProject"
        case .compareOutputs: return "compareOutputs"
        case .followUp: return "followUp"
        case .handoff: return "handoff"
        case .reconcileFinding(let findingID): return "reconcileFinding:\(findingID)"
        case .cloneRepository: return "cloneRepository"
        case .createProject: return "createProject"
        case .task(let taskID): return "task:\(taskID)"
        case .cancelTask(let taskID): return "cancelTask:\(taskID)"
        case .runFocus(let door): return "runFocus:\(door)"
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
    public var filesOpen = false
    public var filesDocked = true
    public var sheet: SheetKind?
    public var decisionsTab: DecisionsTab = .needsAttention
    public var selectedDecisionID: String?
    public var selectedFindingID: String?
    public var selectedRunID: String?
    public var findingFilter: FindingCategory?
    public var selectedOpportunityID: String?
    public var selectedIdeationRunID: String?
    public var ideationFilter: OpportunityVerdict?
    /// The browser's selected file, as a path relative to the project root.
    public var selectedFilePath: String?
    public var settingsSection: SettingsSection = .agentsAndDefaults
    public private(set) var answeredDecisionID: String?
    /// Why the last tracker write failed, already escaped: it is rendered as markdown in a banner.
    public private(set) var trackerError: String?
    public private(set) var isWritingTracker = false

    @ObservationIgnored private let source: ProjectDataSource
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private var isLoading = false

    public init(ref: ProjectRef, source: ProjectDataSource, insightsDelay: Duration = .milliseconds(900),
                runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
        self.ref = ref
        self.source = source
        self.insights = InsightsConversation(delay: insightsDelay)
        if case .local(let path) = ref {
            shellSessions = ShellSessions(projectRoot: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            shellSessions = ShellSessions(projectRoot: nil)
        }
        // A finished run has written whatever it was going to write: read the project again rather than wait to be asked.
        shellSessions.onSessionEnded = { [weak self] _ in
            Task { await self?.load() }
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
    public var ideationCount: Int? { snapshot?.ideation.value?.opportunities.count }
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
            selectedIdeationRunID = loaded.ideation.value?.runs.first?.id
            selectedOpportunityID = loaded.ideation.value?.opportunities.first?.id
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

    /// Every card opens the same dialog over the board. Selecting a card never navigates away from it,
    /// so the board stays where it was and the dialog carries the whole task.
    public func openTask(_ id: String) {
        destination = .board
        lastOpenedTaskID = id
        selectedTaskID = id
        tab = task(id)?.isUnstarted == true ? .requirements : .activity
        sheet = .task(id)
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
        destination = .survey
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

    /// The milestone a card would be queued into; nil when the board could not read one.
    public var activeMilestone: String? { snapshot?.activeMilestone }

    /// A session for `id` is preparing or running. A card says so from this, never by moving column: the
    /// columns are git's (ADR 0011), and a run that has written nothing yet has not changed them.
    public func isRunLive(_ id: String) -> Bool {
        switch shellSessions.state(for: id) {
        case .preparing, .running: return true
        default: return false
        }
    }

    /// True while this task's own run is live, whichever screen started it.
    public func isTaskRunning(_ task: DeskTask) -> Bool {
        guard let number = task.taskNumber else { return false }
        return isRunLive(DoorRuns.id(task: number))
    }

    /// Runs one bounded write from `dev:kanban` Phase 7, then reloads so the board shows what GitHub now says.
    /// A sample project, or a repository with no GitHub remote, is refused rather than half-written.
    public func performTrackerWrite(issue: Int, action: TrackerAction) async {
        guard !isWritingTracker else { return }
        guard let slug = snapshot?.slug, case .local(let path) = ref else {
            trackerError = TrackerWriteError.noRepository.localizedDescription
            return
        }
        isWritingTracker = true
        defer { isWritingTracker = false }
        do {
            let write = TrackerWrite(slug: slug, directory: URL(fileURLWithPath: path, isDirectory: true), runner: runner)
            try await write.perform(issue: issue, action: action)
            trackerError = nil
            await load()
        } catch {
            trackerError = Markdown.escape(error.localizedDescription)
        }
    }

    public func dismissTrackerError() { trackerError = nil }

    public func toggleRuns() { runsOpen.toggle() }

    public func toggleFiles() { filesOpen.toggle() }

    public func dockFiles() {
        filesDocked = true
        filesOpen = true
    }

    public func floatFiles() {
        filesDocked = false
        filesOpen = true
    }

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
