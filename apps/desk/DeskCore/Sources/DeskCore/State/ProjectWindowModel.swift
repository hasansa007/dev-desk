import Foundation
import Observation

public enum Destination: String, CaseIterable, Codable, Hashable {
    case board, terminals, roadmap, findings, ideation, diagrams

    /// What the sidebar calls each place. The raw values are what a window restores its place from, so a
    /// rename that need not change the stored value is made here and never on the case: `terminals` reads
    /// "Sessions" because a chat is one too.
    public var title: String {
        switch self {
        case .terminals: return "Sessions"
        case .board, .roadmap, .findings, .ideation, .diagrams: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public enum TaskTab: String, CaseIterable, Codable, Hashable {
    /// A task is an issue, a diff and evidence. Its session lives in Sessions (ADR 0026), so the dialog has
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
    static func merge(_ message: String) -> WriteFailure { WriteFailure(title: "The report was not merged", message: message) }
    static func update(_ message: String) -> WriteFailure { WriteFailure(title: "The checkout was not updated", message: message) }
    static func stage(_ message: String) -> WriteFailure { WriteFailure(title: "The board was not changed", message: message) }
    static func openFailed(_ message: String) -> WriteFailure { WriteFailure(title: "The file was not opened", message: message) }
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
    case general, appearance, agentsAndDefaults, startWith, accountsAndConnections, notifications, execution, projectOverrides, runProject

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .agentsAndDefaults: return "Agents and defaults"
        case .startWith: return "Start with"
        case .accountsAndConnections: return "Accounts and connections"
        case .notifications: return "Notifications"
        case .execution: return "Execution"
        case .projectOverrides: return "Project overrides"
        case .runProject: return "Run project"
        }
    }
}

public enum SheetKind: Hashable, Identifiable {
    case openProject, compareOutputs, followUp, handoff, reconcileFinding(String), cloneRepository, createProject
    case resetFindings
    case task(String)
    case finding(String)
    case cancelTask(String)
    case runFocus(String)
    case deleteBranch(String)
    case addTask(String)
    /// The start sheet for one task: its launch, and what may carry it (ADR 0036 §4.8 moment 1).
    case startTask(String)
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
        case .resetFindings: return "resetFindings"
        case .task(let taskID): return "task:\(taskID)"
        case .finding(let findingID): return "finding:\(findingID)"
        case .cancelTask(let taskID): return "cancelTask:\(taskID)"
        case .runFocus(let door): return "runFocus:\(door)"
        case .deleteBranch(let branch): return "deleteBranch:\(branch)"
        case .addTask(let column): return "addTask:\(column)"
        case .startTask(let taskID): return "startTask:\(taskID)"
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
    /// How this project runs itself (`.devdesk/run.json`) and the run that is live; its session sits in
    /// `sessions` under a `run:` id. A sample has no folder, so its plan is empty and nothing can start.
    public let projectRuns: ProjectRuns
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
    /// Findings the developer has set aside. A findings reports what the code says; whether a finding is worth
    /// acting on is a judgement the report cannot make, and re-reading the same fifteen items every run is how
    /// a report stops being read at all. Kept per project in the app, never written into `docs/findings/`.
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

    /// The diagram kinds whose `dev:arch` run is in flight right now, so the Diagrams screen can show a spinner
    /// for that kind without switching away from itself. A kind is added when its Generate starts and removed
    /// when the run ends, whatever the run wrote — the screen reads the folder again either way.
    /// Roadmap asked for while Findings was still running: held until that run finishes, then its start sheet
    /// opens. Nil when nothing is waiting.
    public private(set) var roadmapWaitingForFindings: Task<Void, Never>?

    /// Waits for Findings to finish — `findingsInProgress` is read again every few seconds — then re-reads the
    /// project so the new report counts, and opens Roadmap's start sheet if it can now run. The sheet still asks
    /// before anything starts, so a wait that ends while the developer is elsewhere starts nothing unseen.
    public func runRoadmapAfterFindings(findingsInProgress: @escaping @MainActor () -> Bool,
                                        poll: Duration = .seconds(5)) {
        guard roadmapWaitingForFindings == nil else { return }
        roadmapWaitingForFindings = Task { [weak self] in
            while !Task.isCancelled, findingsInProgress() {
                try? await Task.sleep(for: poll)
            }
            guard !Task.isCancelled, let self else { return }
            await self.load()
            self.roadmapWaitingForFindings = nil
            if Self.roadmapBlockedReason(findings: self.snapshot?.findings, findingsInProgress: false) == nil {
                self.present(.runFocus("roadmap"))
            }
        }
    }

    public func cancelRoadmapAfterFindings() {
        roadmapWaitingForFindings?.cancel()
        roadmapWaitingForFindings = nil
    }

    public private(set) var generatingDiagramKinds: Set<String> = []

    /// Which diagram kind each in-flight generate session is drawing, so its end clears the right spinner. A
    /// scratch session runs the headless `dev:arch`; when it ends, this says which kind's run just finished.
    @ObservationIgnored private var generatingSessionKinds: [String: String] = [:]

    /// What a generate that drew nothing leaves for the pane: the run's own evidence, not only a guess.
    public struct DiagramGenerateFailure: Equatable {
        /// What went wrong, leading with the run's own last words when it wrote any, then what the timing
        /// says — an immediate exit is a launch failure, a long run may honestly have declined.
        public let message: String
        /// The last non-empty lines the run wrote, newest last — `JournalRecord.logTail`'s own shape, read
        /// back from the session registry rather than captured a second time.
        public let outputTail: [String]
        /// The scratch session the run lived in. On failure it is kept, not closed, so the transcript the
        /// CLI wrote stays readable — this is what the banner's "open the run" selects in Sessions.
        public let sessionID: String?
    }

    /// A kind whose last generate finished without drawing a file: `dev:arch` can decline (Phase 0 needs a
    /// committed repo it can name and cut a branch in), and a headless run that asks a question nobody answers
    /// exits having written nothing. Rather than drop the pane silently back to "Generate", the screen reads
    /// this and says the run produced no diagram, so a refusal is visible instead of a mystery. Cleared when a
    /// new generate for that kind starts, and when one succeeds.
    public private(set) var diagramGenerateFailures: [String: DiagramGenerateFailure] = [:]

    /// When each kind's in-flight generate began, so its end can tell a run that never really ran (seconds)
    /// from one that worked and declined (minutes). Keyed by kind and overwritten by the next generate, so an
    /// abandoned start cannot grow the table past the five kinds.
    @ObservationIgnored private var generatingKindStarts: [String: Date] = [:]

    public func beginGeneratingDiagram(kind: String, sessionID: String) {
        generatingDiagramKinds.insert(kind)
        generatingSessionKinds[sessionID] = kind
        generatingKindStarts[kind] = Date()
        diagramGenerateFailures[kind] = nil
    }
    public func isGeneratingDiagram(kind: String) -> Bool { generatingDiagramKinds.contains(kind) }
    public func diagramGenerateFailure(kind: String) -> DiagramGenerateFailure? { diagramGenerateFailures[kind] }

    /// The kind a just-ended session was generating, and forgets it; nil when the session was not a generate.
    /// The caller reads the folder again for that kind and takes the finished scratch session off the list.
    @discardableResult
    public func finishGeneratingDiagram(sessionID: String) -> String? {
        guard let kind = generatingSessionKinds.removeValue(forKey: sessionID) else { return nil }
        generatingDiagramKinds.remove(kind)
        return kind
    }

    /// An interactive run stays open after it draws, so its end is not when the drawing arrives. After a reload,
    /// a generating kind whose file is newer than its start is finished: the spinner gives way to the drawing and
    /// the session stays, since the developer may still be talking to it. Returns the kinds it finished.
    @discardableResult
    public func pickUpGeneratedDiagrams() -> [String] {
        var finished: [String] = []
        for (sessionID, kind) in generatingSessionKinds {
            guard let started = generatingKindStarts[kind], let drawn = diagram(kind: kind),
                  drawn.modifiedAt > started else { continue }
            _ = finishGeneratingDiagram(sessionID: sessionID)
            recordDiagramGenerateResult(kind: kind)
            finished.append(kind)
        }
        return finished
    }

    /// Called after a generate's session ends and the project has been re-read: if the kind still has no file,
    /// the run drew nothing, and what is recorded for the pane carries the run's own evidence — its exit
    /// status, the last lines it wrote, and the session they are still readable in — ahead of any guess about
    /// declining. A successful draw clears any old note.
    public func recordDiagramGenerateResult(kind: String, sessionID: String? = nil) {
        let started = generatingKindStarts.removeValue(forKey: kind)
        guard diagram(kind: kind) == nil else {
            diagramGenerateFailures[kind] = nil
            return
        }
        var status: Int32?
        var tail: [String] = []
        if let sessionID {
            if case .ended(_, let ended) = sessions.state(for: sessionID) { status = ended }
            tail = sessions.outputTail(for: sessionID)
        }
        diagramGenerateFailures[kind] = DiagramGenerateFailure(
            message: Self.diagramFailureMessage(lastLine: tail.last, exitStatus: status,
                                                duration: started.map { Date().timeIntervalSince($0) }),
            outputTail: tail, sessionID: sessionID)
    }

    /// Under this many seconds, a run that drew nothing never really ran: `dev:arch` reads the repository,
    /// cuts a branch and calls a renderer — minutes of work — so a run over in seconds died at launch, the
    /// way one whose prompt a variadic flag swallowed did.
    nonisolated static let launchFailureSeconds: TimeInterval = 10

    /// The pane's note for a kind whose run ended with no file: the run's own last line first — what the CLI
    /// printed is the diagnosis — then what the timing says, and only the slow case keeps the guess about
    /// declining. `duration` nil (an end whose start was never seen) reads as the slow case.
    nonisolated static func diagramFailureMessage(lastLine: String?, exitStatus: Int32?, duration: TimeInterval?) -> String {
        var parts: [String] = []
        if let lastLine, !lastLine.isEmpty {
            parts.append("The run ended saying: `\(lastLine.replacingOccurrences(of: "`", with: "'"))`.")
        }
        let status = exitStatus.map { " (exit \($0))" } ?? ""
        if let duration, duration < Self.launchFailureSeconds {
            parts.append("It exited after \(Int(duration.rounded())) s\(status) without drawing this diagram — too fast to have drawn anything, so this is a launch failure, not a refusal.")
        } else {
            parts.append("The last dev:arch run finished\(status) without drawing this diagram. It may have declined — dev:arch draws from a committed repository (it names the repo and cuts a branch before writing).")
        }
        parts.append("Open the run in Sessions to see everything it said.")
        return parts.joined(separator: " ")
    }

    /// The newest diagram of `kind` this project has drawn, read from disk, or nil when none exists yet. The
    /// screen calls this when a kind is selected; a sample has no folder, so it has nothing to show.
    public func diagram(kind: String) -> ArchDiagram? {
        guard let root = snapshot?.repositoryRoot else { return nil }
        return ArchDiagrams.newest(kind: kind, repositoryRoot: root)
    }

    /// Whether a diagram can be drawn here, and why not when it can't — read only where it blocks, which is the
    /// Diagrams generate. `dev:arch` draws from committed code: it pins nodes to a real SHA and cuts a branch
    /// before writing, so a folder that is not a repository, or a repository with no commits, cannot be drawn.
    public enum DiagramRepoState: Equatable {
        /// A real repo with a commit and a remote, or still loading — nothing to offer.
        case ready
        /// A local folder that is not a git repository. Offer `git init`.
        case notARepository
        /// A repository with no commits, so `HEAD` does not resolve and there is no SHA to pin to.
        case noCommits
        /// A committed repo with no `origin` remote, asked for an architecture diagram. Only architecture carries
        /// repository evidence, and Archify checks it against a GitHub `origin` — offer to add the remote. The
        /// other four kinds carry no evidence and draw without one.
        case noRemote
    }

    /// The repo state the Diagrams screen checks before a generate. A sample has no folder to draw from, so it
    /// reads as ready (its own "sample" reason blocks the run elsewhere); a local project needs a repo and a
    /// commit, and a remote only for `architecture`, the one kind whose nodes Archify pins to a GitHub origin.
    public func diagramRepoState(kind: String) -> DiagramRepoState {
        guard case .local = ref, let snapshot else { return .ready }
        guard snapshot.repositoryRoot != nil else { return .notARepository }
        if snapshot.project.headRevision == nil { return .noCommits }
        return kind == "architecture" && snapshot.project.remote == nil ? .noRemote : .ready
    }

    /// Adds an `origin` remote to a committed repo that has none, then reloads. Archify requires a GitHub URL to
    /// validate, so the screen asks for one and passes it here; nothing is pushed. The URL is passed as a single
    /// argv element, never interpolated into a shell string. Returns whether a remote now exists.
    @discardableResult
    public func addGitRemote(url: String) async -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .local(let path) = ref, diagramRepoState(kind: "architecture") == .noRemote, !trimmed.isEmpty else { return false }
        _ = try? await runner.run("git", ["remote", "add", "origin", trimmed],
                                  in: URL(fileURLWithPath: path, isDirectory: true), timeout: CommandTimeout.git)
        await load()
        return diagramRepoState(kind: "architecture") == .ready
    }

    /// Sessions opened for their own sake — not a door's, not a task's. They open at the project root, which
    /// is where you would have opened Terminal yourself.
    public private(set) var scratchTerminals: [String] = []

    /// Never reused, because the count is not an identity: open two, close the first, open another, and
    /// "count + 1" hands out term:2 a second time — two rows with one id, colliding in the list and in the
    /// session registry, so the new terminal draws the old one's frame.
    @ObservationIgnored private var terminalsOpened = 0

    /// A terminal opened from outside the Terminals screen (the menu's New Terminal) whose shell that screen
    /// still has to start — the screen owns the terminal views, so the menu can only ask.
    public var terminalAwaitingStart: String?

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
    /// The width Files opens at: the narrowest its resizer allows, so the tree earns room by being dragged
    /// wider rather than taking it. `DeskMetric.filesWidthRange`'s lower bound is this same number — that
    /// table lives in the app target, which DeskCore cannot see.
    public static let filesWidthMin: Double = 260

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
        projectRuns = ProjectRuns(projectRoot: root, sessions: sessions)
        // A finished run has written whatever it was going to write: read the project again rather than wait to be asked.
        sessions.onSessionEnded = { [weak self] id in
            Task {
                await self?.sync()
                self?.pickUpGeneratedDiagrams()
                if Self.endedRunShowsDiagrams(sessionID: id) { self?.go(.diagrams) }
                // A diagram generate that just finished: its spinner clears, the reload above has already
                // picked up the new file, and on success the scratch session it ran in comes off the list. It
                // never navigates — the Diagrams screen stays put while its own kind swaps from spinner to
                // drawing. When the run drew nothing, a note carrying the run's own exit and last words is
                // recorded, and the session is kept: closing it threw away the transcript that named the
                // failure, and the pane then had nothing truer to say than "it may have declined".
                if let kind = self?.finishGeneratingDiagram(sessionID: id) {
                    self?.recordDiagramGenerateResult(kind: kind, sessionID: id)
                    if self?.diagramGenerateFailure(kind: kind) == nil { self?.closeTerminal(id) }
                }
            }
        }
    }

    public var snapshot: ProjectSnapshot? {
        if case .loaded(let snapshot) = loadState { return snapshot }
        return nil
    }

    /// The board's tasks, with anything live in this window promoted out of the unstarted columns: a card
    /// with a run, shell or agent going is being worked on whatever git has seen, so Backlog with a pulsing
    /// "Running" pill — the report that led to ADR 0035 — cannot happen. The promotion is this window's own
    /// view, never written anywhere: the next load recomputes it from the same facts.
    public var tasks: [DeskTask] { (snapshot?.board.value ?? []).map(promotingRunning) }
    public var selectedTask: DeskTask? { selectedTaskID.flatMap(task) }
    public func task(_ id: String) -> DeskTask? { tasks.first { $0.id == id } }

    /// What a notification calls a session: its door run's or task's title, else the name it started under.
    public func sessionName(_ id: String) -> String {
        runs.runs.first { $0.id == id }?.title ?? task(id)?.title ?? sessions.title(for: id) ?? "A terminal session"
    }
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

    /// What an action brings in from origin before the reload: a fetch, and every local branch fast-forwarded that loses
    /// nothing by it. Only actions call this — opening, ⌘R, a start, a stop, a move, a write — never the timed reload,
    /// so nothing reaches the network while nobody is doing anything.
    public func sync() async {
        if case .local(let path) = ref, !isSyncing {
            isSyncing = true
            lastSync = await OriginSync(root: URL(fileURLWithPath: path, isDirectory: true), runner: runner).run()
            isSyncing = false
        }
        await load()
    }

    public private(set) var isSyncing = false
    /// The last action's fetch, so a failed one can be said rather than silently leaving the board stale.
    public private(set) var lastSync: OriginSync.Result?

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

    /// True when the ended session was the dev:arch door run, so a finished diagram should be shown. Only that
    /// door earns the move: every other ended session leaves you on the screen you were already reading.
    public static func endedRunShowsDiagrams(sessionID: String) -> Bool {
        sessionID == DoorRuns.id(door: "arch")
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

    /// The board card a finding became. A filed finding is not "in backlog" for long — its card moves on to
    /// In progress and Done — so the findings run asks the board where it is rather than remembering where it went.
    public func boardTask(forFinding key: String) -> DeskTask? {
        guard !key.isEmpty, let item = snapshot?.localBacklog.first(where: { $0.key == key }) else { return nil }
        return tasks.first { $0.localBacklogID == item.id }
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

    // MARK: - Board stages (ADR 0035)

    /// A task in an unstarted column with something live here is shown In progress; everything else about
    /// it stays as built. Kept pure and static so the rule is testable without a live shell.
    private func promotingRunning(_ task: DeskTask) -> DeskTask {
        Self.promoted(task, isRunning: activity(of: task) != nil)
    }

    static func promoted(_ task: DeskTask, isRunning: Bool) -> DeskTask {
        guard isRunning, task.column == .backlog || task.column == .readyForDev || task.column == .queued else { return task }
        var task = task
        task.column = .inProgress
        return task
    }

    /// Backlog → Ready for dev: the explicit "this can be picked up" judgement git has no fact for.
    public func moveToReadyForDev(_ task: DeskTask) async { await setStage(.readyForDev, for: task) }

    /// Ready for dev / Queued → Backlog. Clearing the stage is enough: with nothing stored, the card falls
    /// back to git and the milestone, which is what Backlog means.
    public func returnToBacklog(_ task: DeskTask) async { await setStage(nil, for: task) }

    /// Queued / In progress → Ready for dev — but only when that would be true afterwards; see
    /// `stageBackBlockedReason`.
    public func cancelToReadyForDev(_ task: DeskTask) async {
        guard stageBackBlockedReason(for: task) == nil else { return }
        await setStage(.readyForDev, for: task)
    }

    /// A start moves the card to In progress at once, instead of leaving it unstarted until the first
    /// commit finally gives git something to say.
    public func recordStarted(_ task: DeskTask) async { await setStage(.inProgress, for: task) }

    /// A Start made with every slot busy: the card goes to Queued rather than nowhere, and the queue releases
    /// it when one frees.
    public func queueForStart(_ task: DeskTask) async { await setStage(.queued, for: task) }

    /// Why a card cannot be moved back a column, or nil when it can. git owns In progress once commits exist
    /// (ADR 0011), so clearing the stage would leave the card exactly where it is.
    public func stageBackBlockedReason(for task: DeskTask) -> String? {
        guard let branch = task.branch, let count = task.unmergedCount, count > 0 else { return nil }
        return "It has \(count) commit\(count == 1 ? "" : "s") on \(branch) — git decides In progress, so this would not move it."
    }

    /// Writes the stage into `.devdesk/board.json` and reloads, so the board shows the result. Local and
    /// instant: no `gh` command, no network. A `branch:`/`pr:`/`merged:` card is git's own and takes no
    /// stage; a project with no repository root has nowhere to keep one. `BoardStages.write` never throws,
    /// so the file is read back and a stage that did not land is reported rather than silently dropped.
    private func setStage(_ stage: BoardStage?, for task: DeskTask) async {
        await setStage(stage, forTaskID: task.id)
    }

    /// The same write by id alone, for a card that is not on the board yet — a task just typed into Ready
    /// for dev needs its stage recorded before the reload that first shows it.
    private func setStage(_ stage: BoardStage?, forTaskID id: String) async {
        guard let path = snapshot?.repositoryRoot,
              !id.hasPrefix("branch:"), !id.hasPrefix("pr:"), !id.hasPrefix("merged:") else { return }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        BoardStages.read(projectRoot: root).setting(stage, for: id).write(projectRoot: root)
        guard BoardStages.read(projectRoot: root).stages[id] == stage else {
            writeFailure = .stage("The stage could not be written to `\(BoardStages.relativePath)`.")
            return
        }
        writeFailure = nil
        await sync()
    }

    /// A task typed on the board. It is written to `docs/backlog/` (ADR 0027) — instant and local, no
    /// tracker run — and lands in the column it was added from: adding from Ready for dev records that
    /// stage, so the card appears where it was typed rather than at the back of Backlog. Backlog itself
    /// records nothing — it is the absence of a stage.
    @discardableResult
    public func addTask(title: String, notes: String, column: BoardColumn) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let root = snapshot?.repositoryRoot else { return false }
        // Today's date is the entry's key — the date-led name the folder already sorts by — so a task
        // typed today never collides with one typed another day.
        let key = Self.backlogDay.string(from: Date())
        // `LocalBacklog.write` deliberately never overwrites and hands back the existing path, which from
        // this button would look like a press that did nothing — so a name already taken is refused aloud.
        let name = LocalBacklog.fileName(key: key, title: title)
        guard !LocalBacklog.read(projectPath: root).contains(where: { $0.id == name }) else {
            writeFailure = .backlog(Markdown.escape("\(LocalBacklog.folder)/\(name).md already exists, and an entry is never overwritten. Edit that file, or give this task a different title."))
            return false
        }
        do {
            let path = try LocalBacklog.write(projectPath: root, key: key, title: title,
                                              body: notes.trimmingCharacters(in: .whitespacesAndNewlines), source: nil)
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            writeFailure = nil
            if column == .readyForDev { await setStage(.readyForDev, forTaskID: DeskTask.localPrefix + stem) }
            await load()
            return true
        } catch {
            writeFailure = .backlog(Markdown.escape(error.localizedDescription))
            return false
        }
    }

    /// `2026-09-14`, in the fixed locale the board's own formatters use, so the file's name never depends
    /// on the Mac's calendar settings.
    private static let backlogDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Findings reset

    /// How many findings this project has set aside, for the sheet that offers to bring them back.
    public var ignoredFindingsCount: Int { ignoredFindings.count }

    /// Reports a reset would move to the Trash: all of them, newest first.
    public var findingsReports: [String] {
        guard case .local(let path) = ref else { return [] }
        return FindingsCleanup.reports(in: path)
    }

    /// Starts this project's findings reading over. Each part is separately owned — the app's ignored list, the
    /// window's own selection, the repository's older reports — so each is separately asked for.
    /// The board cards this project's findings became, in report order, each once.
    public var findingsFiledCards: [DeskTask] {
        var seen: Set<String> = []
        return (snapshot?.findings.value?.findings ?? []).compactMap { boardTask(forFinding: $0.id) }
            .filter { seen.insert($0.id).inserted }
    }

    public func resetFindings(_ options: FindingsResetOptions) async {
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
        if options.reports, case .local(let path) = ref {
            do {
                try FindingsCleanup.trashReports(in: path)
                writeFailure = nil
            } catch {
                writeFailure = WriteFailure(title: "The reports were not moved to the Trash",
                                            message: Markdown.escape(error.localizedDescription))
            }
        }
        if !options.closeIssues.isEmpty {
            await closeAsNotPlanned(options.closeIssues, reason: options.closeReason)
        }
        if !options.trashBacklogIDs.isEmpty, let root = snapshot?.repositoryRoot {
            var failures: [String] = []
            for item in snapshot?.localBacklog ?? [] where options.trashBacklogIDs.contains(item.id) {
                do { try LocalBacklog.remove(atPath: item.path, projectPath: root) } catch {
                    failures.append("\(item.title): \(error.localizedDescription)")
                }
            }
            if let selected = selectedTaskID, options.trashBacklogIDs.contains(where: { selected == DeskTask.localPrefix + $0 }) {
                selectedTaskID = nil
            }
            if !failures.isEmpty { writeFailure = .backlog(Markdown.escape(failures.joined(separator: "\n"))) }
        }
        await load()
        // A reset leaves the newest run selected, the way opening the project does.
        if options.viewState {
            selectedRunID = snapshot?.findings.value?.runs.first?.id
            selectedFindingID = snapshot?.findings.value?.findings.first?.id
        }
    }

    /// Opens the finding's card, the way a task's card opens: the dialog, not a reading pane. A link from
    /// elsewhere in the app lands on the Findings screen with that finding open on top of it.
    public func openFinding(_ id: String) {
        destination = .findings
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

    /// Whether a findings run in a terminal would clash with one already going here. Passing a scope asks about
    /// that half of the report only — `defects` is free to start beside a live `architecture` run, and both
    /// are refused beside a live `both`, which occupies the whole report. Passing nothing asks the door-wide
    /// question ("is any findings run going?"), which is what resetting findings has to know.
    /// Roadmap builds from what Findings recorded, so it is offered only once there is a finished report: not
    /// before any, and not while a run is still writing one — a roadmap read from half a report proposes from
    /// half the evidence. nil when it can run.
    public nonisolated static func roadmapBlockedReason(findings: Surface<FindingsReport>?, findingsInProgress: Bool) -> String? {
        if findingsInProgress {
            return "Findings is still running. Roadmap builds from its report, so it waits for that run to finish."
        }
        guard let report = findings?.value, !report.runs.isEmpty else {
            return "There are no findings yet. Roadmap builds from what Findings records, so run Findings first."
        }
        return nil
    }

    public func isFindingsRunLive(scope: FindingsRunScope? = nil) -> Bool {
        FindingsRunScope.allCases.contains { live in
            isRunLive(DoorRuns.id(door: "findings", scope: live)) && (scope.map(live.conflicts(with:)) ?? true)
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
            await sync()
        } catch {
            writeFailure = .tracker(Markdown.escape(error.localizedDescription))
        }
    }

    /// The same bounded cancel a card makes, once per issue, reloading once at the end. The ones that failed are
    /// named together, so a close that half-worked says which half.
    func closeAsNotPlanned(_ issues: [Int], reason: String) async {
        guard !isWritingTracker else { return }
        guard let slug = snapshot?.slug, case .local(let path) = ref else {
            writeFailure = .tracker(TrackerWriteError.noRepository.localizedDescription)
            return
        }
        isWritingTracker = true
        defer { isWritingTracker = false }
        let write = TrackerWrite(slug: slug, directory: URL(fileURLWithPath: path, isDirectory: true), runner: runner)
        var failures: [String] = []
        for issue in issues {
            do {
                try await write.perform(issue: issue, action: .cancel(reason: reason))
            } catch {
                failures.append("#\(issue): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { writeFailure = .tracker(Markdown.escape(failures.joined(separator: "\n"))) }
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
            await sync()
        } catch {
            writeFailure = .branch(Markdown.escape(error.localizedDescription))
        }
    }

    /// Approving a finished report merges it into origin's base and pushes; the reload is what moves the card to Done.
    public func approveReport(_ task: DeskTask) async {
        guard !isWritingTracker, task.isFinishedReport, !task.isMerged, let branch = task.branch else { return }
        guard case .local(let path) = ref else {
            writeFailure = .merge(ReportMergeError.notThisRepository.localizedDescription)
            return
        }
        guard let base = ReportMerge.originBase(task.baseRef) else {
            writeFailure = .merge(ReportMergeError.noOriginBase.localizedDescription)
            return
        }
        isWritingTracker = true
        defer { isWritingTracker = false }
        do {
            try await ReportMerge(directory: URL(fileURLWithPath: path, isDirectory: true), runner: runner).merge(branch: branch, base: base)
            writeFailure = nil
        } catch {
            writeFailure = .merge(Markdown.escape(error.localizedDescription))
        }
        await sync()
    }

    /// Brings origin's base into the checked-out branch, only when asked. git refuses when uncommitted changes would be
    /// overwritten, and that refusal is shown as it is; a merge that stops on a conflict is aborted, so the checkout is
    /// left exactly as it was rather than half-merged under whatever is working in it.
    public func updateCheckout() async {
        guard !isWritingTracker, case .local(let path) = ref, let behind = snapshot?.checkoutBehind else { return }
        isWritingTracker = true
        defer { isWritingTracker = false }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        // With uncommitted changes a conflicted merge cannot be backed out cleanly (`merge --abort` may lose them), so it is not started.
        let status = try? await runner.run("git", GitCommand.read(["status", "--porcelain", "--untracked-files=no"]), in: root, timeout: CommandTimeout.git)
        guard let status, status.succeeded, status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            writeFailure = .update(Markdown.escape("\(behind.branch) has uncommitted changes. Commit them first, then Update merges origin/\(behind.base) in."))
            return
        }
        let merge = try? await runner.run("git", GitCommand.commit(["merge", "--no-edit", "refs/remotes/origin/\(behind.base)"]),
                                          in: root, timeout: CommandTimeout.worktreeAdd)
        if let merge, merge.succeeded {
            writeFailure = nil
        } else {
            let reason = merge.flatMap { GitOutput.lastNonEmptyLine($0.stderr) ?? GitOutput.lastNonEmptyLine($0.stdout) } ?? "git merge did not finish"
            _ = try? await runner.run("git", GitCommand.read(["merge", "--abort"]), in: root, timeout: CommandTimeout.git)
            writeFailure = .update(Markdown.escape("origin/\(behind.base) was not merged into \(behind.branch): \(reason)"))
        }
        await sync()
    }

    public func dismissWriteFailure() { writeFailure = nil }

    public func toggleRuns() { runsOpen.toggle() }

    /// Opening Files starts it at its floor; a width you dragged belongs to that opening, not to every later one.
    public func toggleFiles() {
        filesOpen.toggle()
        if filesOpen { filesWidth = Self.filesWidthMin }
    }

    public func showRuns() { runsOpen = true }

    /// Asking for a panel that is already open leaves the width you gave it alone.
    public func showFiles() {
        guard !filesOpen else { return }
        filesOpen = true
        filesWidth = Self.filesWidthMin
    }

    // MARK: - The selected file

    /// The project's folder on disk; a sample has none, so nothing of it can be read or opened.
    public var projectRoot: URL? {
        if case .local(let path) = ref { return URL(fileURLWithPath: path, isDirectory: true) }
        return nil
    }

    /// The absolute `file://` URL a tree path names under `root`, or nil when it is not a path inside it.
    /// Standardized before the check, because `root/../x` names a real file outside the project and `root/./x`
    /// names one LaunchServices declines; and an id that is already absolute is not a relative path at all —
    /// appending one built `root` + that whole path, which names nothing and opened nothing.
    public static func fileURL(root: URL, relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }
        let url = root.appendingPathComponent(trimmed).standardizedFileURL
        guard url.isFileURL, SafeFile.isInside(url, root) else { return nil }
        return url
    }

    /// The selected file's URL: nil when nothing is selected, the project has no folder, or the path escapes it.
    public var selectedFileURL: URL? {
        guard let root = projectRoot, let path = selectedFilePath else { return nil }
        return Self.fileURL(root: root, relativePath: path)
    }

    /// Dismisses the viewer. The tree it was opened from stays where it is.
    public func closeFile() { selectedFilePath = nil }

    /// How a file is handed to the system's own editor. `NSWorkspace` is AppKit, so the app target installs the
    /// call and this model only decides when to make it; a message back is the system's refusal, nil is success.
    @ObservationIgnored public var editorOpen: ((URL) async -> String?)?

    /// Opens a file and says so when the system would not: the Bool the old `NSWorkspace.open(_:)` returned was
    /// thrown away, which made a refused open indistinguishable from a dead button.
    public func openFile(_ url: URL) {
        guard let editorOpen else {
            writeFailure = .openFailed("This window cannot open files.")
            return
        }
        Task { [weak self] in
            let refusal = await editorOpen(url)
            guard let self else { return }
            if let refusal {
                self.writeFailure = .openFailed(Markdown.escape(refusal))
            } else {
                self.writeFailure = nil
            }
        }
    }

    /// The selected file, opened. A path that escapes the project is reported rather than silently doing nothing.
    public func openSelectedFile() {
        guard let url = selectedFileURL else {
            writeFailure = .openFailed("This file is not inside the project, so it was not opened.")
            return
        }
        openFile(url)
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
