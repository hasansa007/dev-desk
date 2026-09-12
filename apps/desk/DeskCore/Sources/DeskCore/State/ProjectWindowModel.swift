import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, roadmap, survey, ideation, insights
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum TaskTab: String, CaseIterable, Codable, Hashable {
    case activity, requirements, changes, evidence, shell, agent
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum ViewMode: String, Codable, Hashable { case focus, parallel }

/// The kinds of live work a card can carry. They are the app's own process state, never a claim about git's columns.
public enum TaskActivity: String, Hashable {
    /// A door this window started for the task — `/dev #N` and its kin.
    case run
    /// The task's own login shell, started from its dialog.
    case shell
    /// Claude Code or Codex, started by you or by Auto.
    case agent

    public var label: String {
        switch self {
        case .run: return "Running"
        case .shell: return "Shell"
        case .agent: return "Agent"
        }
    }
}

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
    case settings

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
        case .settings: return "settings"
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
    /// Each task's agent in this window, in the same folders as the shells; a sample's can't start either.
    public let agentSessions: ShellSessions
    public private(set) var loadState: LoadState = .loading
    public private(set) var reloadError: String?
    /// When the last load succeeded; nil until one has.
    public private(set) var lastLoadedAt: Date?
    /// True while a load runs, for the toolbar's progress indicator.
    public private(set) var isRefreshing = false
    public var destination: Destination = .board
    public var selectedTaskID: String?
    public private(set) var lastOpenedTaskID: String?
    public var tab: TaskTab = .activity
    public var mode: ViewMode = .focus
    public var showBacklog = false
    public var searchText = ""
    /// Both panels are edges of the window, never floating windows over it: Runs along the bottom, Files down
    /// the right. Open is all there is to say about one.
    public var runsOpen = false
    public var filesOpen = false
    public var sheet: SheetKind?
    public var selectedFindingID: String?
    public var selectedRunID: String?
    public var findingFilter: FindingCategory?
    public var selectedOpportunityID: String?
    public var selectedIdeationRunID: String?
    public var ideationFilter: OpportunityVerdict?
    /// The browser's selected file, as a path relative to the project root.
    public var selectedFilePath: String?
    public var settingsSection: SettingsSection = .agentsAndDefaults
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
        var root: URL?
        if case .local(let path) = ref { root = URL(fileURLWithPath: path, isDirectory: true) }
        shellSessions = ShellSessions(projectRoot: root)
        agentSessions = ShellSessions(projectRoot: root, purpose: .agent)
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
    public var parallelTasks: [DeskTask] { Array(tasks.filter { $0.column == .inProgress && !$0.parallel.isNone }.prefix(4)) }

    /// Loads or reloads the snapshot; the launch selection applies only to the first load. A call made while one runs, or a cancelled load, changes nothing.
    public func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let isFirstLoad = snapshot == nil
        do {
            let loaded = try await source.load()
            guard !Task.isCancelled else { return }
            loadState = .loaded(loaded)
            reloadError = nil
            lastLoadedAt = Date()
            guard isFirstLoad else { return }
            insights.configure(loaded.insights)
            selectedTaskID = loaded.launch.selectedTaskID
            lastOpenedTaskID = loaded.launch.selectedTaskID
            selectedRunID = loaded.findings.value?.runs.first?.id
            selectedFindingID = loaded.findings.value?.findings.first?.id
            selectedIdeationRunID = loaded.ideation.value?.runs.first?.id
            selectedOpportunityID = loaded.ideation.value?.opportunities.first?.id
        } catch {
            guard !Task.isCancelled else { return }
            if isFirstLoad { loadState = .failed(error.localizedDescription) } else { reloadError = error.localizedDescription }
        }
    }

    /// Reloads a local project every `interval` until the calling task is cancelled; a sample has nothing new to read.
    /// The gap between automatic reloads, shared by the window that schedules them and the toolbar that counts
    /// down to the next one, so the ring can never drain at a different rate than the thing it is timing.
    public static let refreshSeconds: Double = 120

    public func refresh(every interval: Duration) async {
        guard case .local = ref else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// "Updated just now", then seconds, then whole minutes, for the toolbar.
    public static func updatedLabel(since date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds) s ago" }
        return "Updated \(seconds / 60) min ago"
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
        // Decisions is no longer a destination: a waiting question lives on the task it belongs to.
        case .answerDecision: if let id = selectedTaskID ?? lastOpenedTaskID { sheet = .task(id) }
        case .startHandoff: sheet = .handoff
        case .openURL(let url, _): return url
        }
        return nil
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
        // A desk://decision link has nowhere to go now; the ADR it names is readable in the Files panel.
        case .decision: break
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

    /// What this task has live right now, whichever screen started it — a door run, its own shell, or its agent.
    /// Asking only about the door run is what left a started shell and a started agent invisible on the board.
    public func activity(of task: DeskTask) -> TaskActivity? {
        Self.activity(doorRun: task.taskNumber.map { isRunLive(DoorRuns.id(task: $0)) } ?? false,
                      agent: agentSessions.state(for: task.id),
                      shell: shellSessions.state(for: task.id))
    }

    /// The precedence, apart from the sessions that hold it: a door run speaks for the whole task, an agent for
    /// the work, a shell only for a window someone opened. The first that is live is what the card says.
    static func activity(doorRun: Bool, agent: ShellSessionState, shell: ShellSessionState) -> TaskActivity? {
        if doorRun { return .run }
        if isLive(agent) { return .agent }
        if isLive(shell) { return .shell }
        return nil
    }

    public func isTaskRunning(_ task: DeskTask) -> Bool { activity(of: task) != nil }

    /// How many of a column's cards are live, for the column's own header.
    public func liveCount(in column: BoardColumn) -> Int {
        tasks.filter { $0.column == column && isTaskRunning($0) }.count
    }

    private static func isLive(_ state: ShellSessionState) -> Bool {
        switch state {
        case .preparing, .running: return true
        default: return false
        }
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

    public func showRuns() { runsOpen = true }

    public func showFiles() { filesOpen = true }

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
