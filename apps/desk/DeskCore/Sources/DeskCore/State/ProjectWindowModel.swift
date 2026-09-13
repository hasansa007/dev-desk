import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, terminals, roadmap, survey, ideation, insights
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum TaskTab: String, CaseIterable, Codable, Hashable {
    /// A task is an issue, a diff and evidence. Its session lives in Terminals (ADR 0026), so the dialog has
    /// no pane of its own — two hosts for one terminal is what made a dialog open on an empty frame.
    case activity, requirements, changes, evidence
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum ViewMode: String, Codable, Hashable { case focus, parallel }

/// A failed write, carrying the title of what it failed to change: deleting a branch never touches the tracker,
/// so a banner that says "The tracker was not changed" about it is a false statement, not a reassurance.
public struct WriteFailure: Equatable {
    public let title: String
    public let message: String

    static func tracker(_ message: String) -> WriteFailure { WriteFailure(title: "The tracker was not changed", message: message) }
    static func branch(_ message: String) -> WriteFailure { WriteFailure(title: "The branch was not deleted", message: message) }
    static func backlog(_ message: String) -> WriteFailure { WriteFailure(title: "docs/backlog/ was not changed", message: message) }
}

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
    case resetSurvey
    case task(String)
    case finding(String)
    case cancelTask(String)
    case runFocus(String)
    case deleteBranch(String)
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
        case .resetSurvey: return "resetSurvey"
        case .task(let taskID): return "task:\(taskID)"
        case .finding(let findingID): return "finding:\(findingID)"
        case .cancelTask(let taskID): return "cancelTask:\(taskID)"
        case .runFocus(let door): return "runFocus:\(door)"
        case .deleteBranch(let branch): return "deleteBranch:\(branch)"
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
    /// The doors this window has started; their shells live in `sessions` under the same ids.
    public let runs = DoorRuns()
    /// Each task's shell in this window. A sample has no folder, so none of its sessions can start.
    public let sessions: ShellSessions
    /// Each task's agent in this window, in the same folders as the shells; a sample's can't start either.
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
    /// Which session the Terminals destination has in front, when more than one is live.
    public var selectedSessionID: String?
    /// Findings the developer has set aside. A survey reports what the code says; whether a finding is worth
    /// acting on is a judgement the report cannot make, and re-reading the same fifteen items every run is how
    /// a report stops being read at all. Kept per project in the app, never written into `docs/survey/`.
    public var ignoredFindings: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey(ref)) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.ignoredKey(ref)) }
    }

    public func ignoreFinding(_ id: String) {
        ignoredFindings.insert(id)
        if selectedFindingID == id { selectedFindingID = nil }
    }

    public func restoreFinding(_ id: String) { ignoredFindings.remove(id) }

    /// Ignored findings leave the category lists entirely; this chip is how they are seen again.
    public var showsIgnoredFindings = false

    static func ignoredKey(_ ref: ProjectRef) -> String { "desk.ignoredFindings.\(ref.id)" }

    /// Terminals opened for their own sake — not a door's, not a task's. They open at the project root, which
    /// is where you would have opened Terminal yourself.
    public private(set) var scratchTerminals: [String] = []

    /// Never reused, because the count is not an identity: open two, close the first, open another, and
    /// "count + 1" hands out term:2 a second time — two rows with one id, colliding in the list and in the
    /// session registry, so the new terminal draws the old one's frame.
    @ObservationIgnored private var terminalsOpened = 0

    @discardableResult
    public func newTerminal() -> String {
        terminalsOpened += 1
        let id = "term:\(terminalsOpened)"
        scratchTerminals.append(id)
        selectedSessionID = id
        return id
    }

    /// Only when nothing of it is live: closing a row must never orphan the process behind it.
    public func closeTerminal(_ id: String) {
        guard !sessions.state(for: id).isLive else { return }
        scratchTerminals.removeAll { $0 == id }
    }
    public var mode: ViewMode = .focus
    public var showBacklog = false
    public var searchText = ""
    /// How deep the Runs edge is and how wide the Files edge is. An edge you cannot resize is a decision made
    /// once for every project and every screen size.
    public var runsHeight: Double = 300
    public var filesWidth: Double = 420

    /// Both panels are edges of the window, never floating windows over it: Runs along the bottom, Files down
    /// the right. Open is all there is to say about one.
    public var runsOpen = false
    public var filesOpen = false
    public var sheet: SheetKind?
    public var selectedFindingID: String?
    public var selectedRunID: String?
    public var findingFilter: FindingCategory?
    /// Architecture or defect, the other half of what a finding is. It filters beside the category rather
    /// than inside it: "New" and "Architecture" are different questions about the same finding.
    public var findingKindFilter: FindingKind?
    public var selectedOpportunityID: String?
    public var selectedIdeationRunID: String?
    public var ideationFilter: OpportunityVerdict?
    /// The browser's selected file, as a path relative to the project root.
    public var selectedFilePath: String?
    public var settingsSection: SettingsSection = .agentsAndDefaults
    /// Why the last tracker write failed, already escaped: it is rendered as markdown in a banner.
    public private(set) var writeFailure: WriteFailure?
    public private(set) var isWritingTracker = false

    @ObservationIgnored private let source: ProjectDataSource
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private var isLoading = false

    public init(ref: ProjectRef, source: ProjectDataSource, insightsDelay: Duration = .milliseconds(900),
                runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
        self.ref = ref
        self.source = source
        self.insights = InsightsConversation(delay: insightsDelay, runner: runner)
        var root: URL?
        if case .local(let path) = ref { root = URL(fileURLWithPath: path, isDirectory: true) }
        sessions = ShellSessions(projectRoot: root)
        // A finished run has written whatever it was going to write: read the project again rather than wait to be asked.
        sessions.onSessionEnded = { [weak self] _ in
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

    /// The gap between automatic reloads, shared by the window that schedules them and the ring that counts down.
    public static let refreshSeconds: Double = 120

    /// Reloads a local project every `interval` until the calling task is cancelled; a sample has nothing new to read.
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
        openTaskHere(id)
    }

    /// The same dialog, opened over the screen that asked for it. The roadmap is a view of the board's own
    /// issues, so reading one there should not move you to the board and leave you to find your way back.
    public func openTaskHere(_ id: String) {
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

    // MARK: - Local backlog (ADR 0027)

    /// Whether this item is already in a backlog — `docs/backlog/`, or promoted out of it into an issue. What
    /// filed it must not offer to file it again, and a reload must not forget that it did.
    public func isInLocalBacklog(_ key: String) -> Bool {
        guard let snapshot, !key.isEmpty else { return false }
        return snapshot.localBacklog.contains { $0.key == key } || snapshot.filedBacklogKeys.contains(key)
    }

    public func localBacklogItem(for task: DeskTask) -> BacklogItem? {
        guard let id = task.localBacklogID else { return nil }
        return snapshot?.localBacklog.first { $0.id == id }
    }

    /// Writes the draft into `docs/backlog/` and reloads, so its card is on the board by the time you look.
    /// Instant and local: no agent, no run, nothing to stall — there is no tracker for one to talk to.
    public func fileLocally(_ draft: BacklogDraft) async {
        guard let root = snapshot?.repositoryRoot else { return }
        do {
            try LocalBacklog.write(projectPath: root, key: draft.key, title: draft.title, body: draft.body,
                                   area: draft.area, source: draft.source)
            writeFailure = nil
            await load()
        } catch {
            writeFailure = .backlog(Markdown.escape(error.localizedDescription))
        }
    }

    /// To the Trash, so a removal has the undo the app does not otherwise offer.
    public func removeLocalItem(_ task: DeskTask) async {
        guard let root = snapshot?.repositoryRoot, let item = localBacklogItem(for: task) else { return }
        do {
            try LocalBacklog.remove(atPath: item.path, projectPath: root)
            writeFailure = nil
            if selectedTaskID == task.id { selectedTaskID = nil }
            await load()
        } catch {
            writeFailure = .backlog(Markdown.escape(error.localizedDescription))
        }
    }

    /// Called when a promoting run has reported its issue: GitHub owns the item now, and the file becomes history.
    public func markLocalItemFiled(entry: String, issue number: Int) async {
        guard let root = snapshot?.repositoryRoot,
              let item = snapshot?.localBacklog.first(where: { $0.id == entry }) else { return }
        do {
            try LocalBacklog.markFiled(number, atPath: item.path, projectPath: root)
            writeFailure = nil
            await load()
        } catch {
            writeFailure = .backlog(Markdown.escape(error.localizedDescription))
        }
    }

    // MARK: - Survey reset

    /// How many findings this project has set aside, for the sheet that offers to bring them back.
    public var ignoredFindingsCount: Int { ignoredFindings.count }

    /// Reports a cleanup would move to the Trash: every one but the newest.
    public var olderSurveyReports: [String] {
        guard case .local(let path) = ref else { return [] }
        return SurveyCleanup.olderReports(in: path)
    }

    /// Starts this project's survey reading over. Each part is separately owned — the app's ignored list, the
    /// window's own selection, the repository's older reports — so each is separately asked for.
    public func resetSurvey(_ options: SurveyResetOptions) async {
        guard !options.isEmpty else { return }
        if options.ignoredFindings {
            ignoredFindings = []
            showsIgnoredFindings = false
        }
        if options.viewState {
            selectedFindingID = nil
            selectedRunID = nil
            findingFilter = nil
            findingKindFilter = nil
        }
        if options.olderReports, case .local(let path) = ref {
            do {
                try SurveyCleanup.trashOlderReports(in: path)
                writeFailure = nil
            } catch {
                writeFailure = WriteFailure(title: "The reports were not moved to the Trash",
                                            message: Markdown.escape(error.localizedDescription))
            }
        }
        await load()
        // A reset leaves the newest run selected, the way opening the project does.
        if options.viewState {
            selectedRunID = snapshot?.findings.value?.runs.first?.id
            selectedFindingID = snapshot?.findings.value?.findings.first?.id
        }
    }

    /// Opens the finding's card, the way a task's card opens: the dialog, not a reading pane. A link from
    /// elsewhere in the app lands on the survey screen with that finding open on top of it.
    public func openFinding(_ id: String) {
        destination = .survey
        findingFilter = nil
        findingKindFilter = nil
        showsIgnoredFindings = ignoredFindings.contains(id)
        selectedFindingID = id
        present(.finding(id))
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
        switch sessions.state(for: id) {
        case .preparing, .running: return true
        default: return false
        }
    }

    /// Whether this door already has a run of its own live in this window — the one a second press is refused.
    public func isDoorRunning(_ door: String) -> Bool { isRunLive(DoorRuns.id(door: door)) }

    /// Whether a survey in a terminal would clash with one already going here. Passing a scope asks about
    /// that half of the report only — `defects` is free to start beside a live `architecture` run, and both
    /// are refused beside a live `both`, which occupies the whole report. Passing nothing asks the door-wide
    /// question ("is any survey going?"), which is what resetting the survey has to know.
    public func isSurveyRunning(scope: SurveyRunScope? = nil) -> Bool {
        SurveyRunScope.allCases.contains { live in
            isRunLive(DoorRuns.id(door: "survey", scope: live)) && (scope.map(live.conflicts(with:)) ?? true)
        }
    }

    /// What this task has live right now, whichever screen started it — a door run, its own shell, or its agent.
    public func activity(of task: DeskTask) -> TaskActivity? {
        let doorRun = task.taskNumber.map { isRunLive(DoorRuns.id(task: $0)) }
            ?? task.localBacklogID.map { isRunLive(DoorRuns.id(local: $0)) } ?? false
        return Self.activity(doorRun: doorRun,
                      session: sessions.state(for: task.id),
                      purpose: sessions.purpose(for: task.id))
    }

    /// A door run speaks for the whole task; otherwise the task's own session speaks, and says which kind it is.
    /// One session per task (ADR 0026), so there is nothing left to rank.
    static func activity(doorRun: Bool, session: ShellSessionState, purpose: SessionPurpose?) -> TaskActivity? {
        if doorRun { return .run }
        guard session.isLive else { return nil }
        return purpose == .agent ? .agent : .shell
    }

    public func isTaskRunning(_ task: DeskTask) -> Bool { activity(of: task) != nil }

    /// A header describes its column, not the search box, so both numbers count every card in it.
    public func counts(in column: BoardColumn) -> (total: Int, live: Int) {
        let cards = tasks.filter { $0.column == column }
        return (cards.count, cards.filter { isTaskRunning($0) }.count)
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
            writeFailure = .tracker(TrackerWriteError.noRepository.localizedDescription)
            return
        }
        isWritingTracker = true
        defer { isWritingTracker = false }
        do {
            let write = TrackerWrite(slug: slug, directory: URL(fileURLWithPath: path, isDirectory: true), runner: runner)
            try await write.perform(issue: issue, action: action)
            writeFailure = nil
            await load()
        } catch {
            writeFailure = .tracker(Markdown.escape(error.localizedDescription))
        }
    }

    /// Deletes a local branch: one bounded command, and `force` only ever true once its name has been typed.
    public func deleteBranch(_ name: String, force: Bool) async {
        guard !isWritingTracker else { return }
        guard case .local(let path) = ref else {
            writeFailure = .branch(BranchWriteError.notThisRepository.localizedDescription)
            return
        }
        isWritingTracker = true
        defer { isWritingTracker = false }
        do {
            let write = BranchWrite(directory: URL(fileURLWithPath: path, isDirectory: true), runner: runner)
            try await write.delete(branch: name, force: force)
            writeFailure = nil
            await load()
        } catch {
            writeFailure = .branch(Markdown.escape(error.localizedDescription))
        }
    }

    public func dismissWriteFailure() { writeFailure = nil }

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
