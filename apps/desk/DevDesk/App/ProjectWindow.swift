import DeskCore
import SwiftUI

struct ProjectWindow: View {
    let ref: ProjectRef
    @State private var model: ProjectWindowModel
    /// This window's sessions — one per task, shell or agent (ADR 0026); closing the window or quitting ends them.
    @State private var terminals: ShellTerminalRegistry
    @State private var auto: AutoAgents
    /// Drains the cards a Start parked in Queued (ADR 0035); it runs whether or not Auto is on.
    @State private var queue: StartQueueRunner
    @State private var layoutRestored = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @Environment(OpenProjectRegistry.self) private var registry
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    /// Asked for by hand. A window narrower than the breakpoint takes the rail anyway — an open sidebar there
    /// leaves the board no room — and gets the choice back when it widens.
    @AppStorage(PreferenceKey.sidebarRail) private var railMode = false
    @AppStorage(PreferenceKey.autoReload) private var autoReload = false
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @SceneStorage("desk.destination") private var storedDestination: Destination?
    @SceneStorage("desk.taskID") private var storedTaskID: String?
    @SceneStorage("desk.tab") private var storedTab: TaskTab?

    init(ref: ProjectRef) {
        self.ref = ref
        let model = ProjectWindowModel(ref: ref, source: DataSources.make(for: ref))
        // The model decides when a file is opened; `NSWorkspace` is AppKit's, so the app target says how.
        model.editorOpen = { await FileOpen.inEditor($0) }
        _model = State(initialValue: model)
        let terminals = ShellTerminalRegistry(sessions: model.sessions)
        _terminals = State(initialValue: terminals)
        _auto = State(initialValue: AutoAgents(model: model, agents: terminals))
        _queue = State(initialValue: StartQueueRunner(model: model))
    }

    var body: some View {
        GeometryReader { proxy in
            window(size: proxy.size)
                // Measured once and handed down, because a sheet cannot measure the window it covers.
                .environment(\.deskWindowSize, proxy.size)
        }
        .frame(minWidth: DeskMetric.windowMinWidth, minHeight: DeskMetric.windowMinHeight)
    }

    private func window(size: CGSize) -> some View {
        let isRail = railMode || size.width < DeskMetric.railBreakpoint
        return NavigationSplitView(columnVisibility: $columns) {
            Sidebar(model: model, isRail: isRail)
                .navigationSplitViewColumnWidth(isRail ? DeskMetric.sidebarRailWidth : DeskMetric.sidebarWidth)
        } detail: {
            ContentRouter(model: model)
        }
        .toolbar { ProjectToolbar(model: model, terminals: terminals, columns: $columns) }
        .navigationTitle(model.snapshot?.project.name ?? ref.displayName)
        .navigationSubtitle(subtitle)
        .sheet(item: $model.sheet) { kind in
            SheetHost(model: model, kind: kind)
        }
        .modifier(DeskLinkRouting(model: model))
        .environment(\.terminals, terminals)
        .focusedSceneValue(\.projectModel, model)
        .preferredColorScheme(SnapshotMode.shared.colorScheme ?? appearance.colorScheme)
        .background { windowHooks }
        .task { await model.sync() }
        .onChange(of: model.windowCommand) { _, request in
            guard let request else { return }
            model.windowCommand = nil
            switch request.command {
            case .run:
                if let target = model.runTarget {
                    model.requestProjectRun(target: target, terminals: terminals, worktreeLocation: worktreeLocation)
                }
            case .stop:
                let target = model.runTarget?.folder.standardizedFileURL
                let runs = model.projectRuns
                // The run in the folder ⌘R would target, else whatever is live.
                let id = runs.sessionIDs.first { runs.isLive(sessionID: $0) && runs.sessionFolders[$0].map { URL(fileURLWithPath: $0).standardizedFileURL } == target }
                    ?? runs.liveSessionID
                if let id { model.stopProjectRun(sessionID: id, terminals: terminals) }
            }
        }
        .confirmationDialog(model.pendingRunReplacement.map { "\($0.configurationName) is running on \($0.liveBranch)" } ?? "",
                            isPresented: Binding(get: { model.pendingRunReplacement != nil },
                                                 set: { if !$0 { model.pendingRunReplacement = nil } }),
                            titleVisibility: .visible) {
            Button("Stop it and run \(model.pendingRunReplacement?.branch ?? "here")") {
                model.confirmRunReplacement(terminals: terminals, worktreeLocation: worktreeLocation)
            }
            Button("Cancel", role: .cancel) { model.pendingRunReplacement = nil }
        } message: {
            Text("Both would use the same port, so only one run of a configuration goes at a time.")
        }
        // Restarted by the toggle: turning it off cancels the loop, turning it on starts a fresh one.
        .task(id: autoReload) {
            if autoReload, !SnapshotMode.shared.isActive { await model.refresh(every: .seconds(ProjectWindowModel.refreshSeconds)) }
        }
        .onChange(of: model.snapshot != nil) { _, isLoaded in
            if isLoaded { applyFirstLoad() }
        }
        .onAppear {
            registry.windowOpened(ref)
            terminals.onEvent = { [model, ref, terminals] id, event in
                guard case .local(let path) = ref else { return }
                if event == .turnFinished, model.liveSessionsOfDoneTasks.contains(id) { Self.closeDone(model: model, terminals: terminals) }
                let onScreen = NSApp.isActive && model.destination == .terminals && model.selectedSessionID == id
                RunNotifications.post(event, session: id, name: model.sessionName(id), directory: path, isOnScreen: onScreen)
            }
        }
        .onChange(of: model.liveSessionsOfDoneTasks) { _, _ in Self.closeDone(model: model, terminals: terminals) }
        .onReceive(NotificationCenter.default.publisher(for: RunNotifications.openSession)) { note in
            guard case .local(let path) = ref, note.userInfo?["directory"] as? String == path else { return }
            if let session = note.userInfo?["session"] as? String { model.selectedSessionID = session }
            model.go(.terminals)
        }
        .onDisappear { registry.windowClosed(ref) }
        .onChange(of: model.destination) { _, value in if layoutRestored { storedDestination = value } }
        .onChange(of: model.selectedTaskID) { _, value in if layoutRestored { storedTaskID = value ?? "" } }
        .onChange(of: model.tab) { _, value in if layoutRestored { storedTab = value } }
    }

    /// Snapshot mode's capture, ending the window's sessions when it closes, and its Auto loop.
    @ViewBuilder private var windowHooks: some View {
        SnapshotWindowHook(ref: ref, model: model)
        ShellLifetimeHook(registries: [terminals])
        AutoAgentsHook(auto: auto, ref: ref)
        StartQueueHook(queue: queue)
        FiledWorkHook(model: model)
    }

    /// Ends and takes off the list each Done task's session, except an agent still mid-turn: its turn's end calls this again.
    @MainActor
    private static func closeDone(model: ProjectWindowModel, terminals: ShellTerminalRegistry) {
        for id in model.liveSessionsOfDoneTasks where !terminals.isMidTurn(id) {
            terminals.end(taskID: id)
            model.runs.remove(id)
        }
    }

    private var subtitle: String {
        guard let project = model.snapshot?.project, !project.branch.isEmpty else { return "" }
        return "\(project.displayPath) · \(project.branch)"
    }

    /// Runs once, after whichever load succeeds first, so a Retry after a failed first load still restores and records.
    private func applyFirstLoad() {
        guard !layoutRestored else { return }
        layoutRestored = true
        guard !SnapshotMode.shared.isActive else { return }
        restoreLayout()
        recordRecent()
    }

    /// An empty stored task id means the board was showing no task; an id that no longer exists is ignored.
    private func restoreLayout() {
        if let storedTaskID {
            if storedTaskID.isEmpty {
                model.selectedTaskID = nil
            } else if model.task(storedTaskID) != nil {
                model.openTask(storedTaskID)
            }
        }
        if let storedDestination { model.destination = storedDestination }
        if let storedTab { model.tab = storedTab }
    }

    private func recordRecent() {
        guard case .local = ref, let project = model.snapshot?.project else { return }
        AppServices.recents.record(ref, name: project.name, displayPath: project.displayPath)
    }
}

/// A background door that files or edits an issue changes the tracker this window is reading, and nothing on
/// screen knows that. Rather than wait out the refresh interval, reload as soon as one finishes here: filing
/// is supposed to put a card on the board, and a board that only catches up a minute later reads as filing
/// having done nothing.
///
/// It also finishes a promotion (ADR 0027): when a run filing a `docs/backlog/` entry reports its issue, the
/// entry is moved to `filed/` so GitHub owns it from then on. A run that reports no number leaves the file
/// where it is — guessing which issue it made is how an entry gets marked as the wrong one.
private struct FiledWorkHook: View {
    let model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var settled: Set<String> = []

    /// Finished runs in THIS project, by id. A change means one just ended — and jobs from another window's
    /// project never move it.
    private var finishedHere: [BackgroundJob] {
        guard let jobs, case .local(let path) = model.ref else { return [] }
        return jobs.jobs.filter { $0.directory == path && !$0.state.isLive }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: finishedHere.map(\.id)) { _, _ in settle() }
    }

    private func settle() {
        let fresh = finishedHere.filter { !settled.contains($0.id) }
        guard !fresh.isEmpty else { return }
        settled.formUnion(fresh.map(\.id))
        Task {
            for job in fresh {
                guard job.door == "create-issue", let subject = job.subject, subject.hasPrefix(DeskTask.localPrefix),
                      case .ended(let text, false) = job.state,
                      let number = LocalBacklog.issueNumber(inRunResult: text, slug: model.snapshot?.slug) else { continue }
                await model.markLocalItemFiled(entry: String(subject.dropFirst(DeskTask.localPrefix.count)), issue: number)
            }
            await model.sync()
        }
    }
}

/// Routes `desk://` links in-app and lets only web and mail links leave it; any other scheme a repository's text carries is discarded unopened.
struct DeskLinkRouting: ViewModifier {
    let model: ProjectWindowModel

    static func opensExternally(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            if let link = DeskLink(url: url) {
                model.handle(link)
                return .handled
            }
            return Self.opensExternally(url) ? .systemAction : .discarded
        })
    }
}

extension ProjectRef {
    var displayName: String {
        switch self {
        case .sample(let project): return project.title
        case .local(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}
