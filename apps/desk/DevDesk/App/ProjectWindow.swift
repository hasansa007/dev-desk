import DeskCore
import SwiftUI

struct ProjectWindow: View {
    let ref: ProjectRef
    @State private var model: ProjectWindowModel
    /// This window's shells and agents; closing the window or quitting ends them.
    @State private var terminals: ShellTerminalRegistry
    @State private var agents: ShellTerminalRegistry
    @State private var auto: AutoAgents
    @State private var layoutRestored = false
    @Environment(OpenProjectRegistry.self) private var registry
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    @SceneStorage("desk.destination") private var storedDestination: Destination?
    @SceneStorage("desk.taskID") private var storedTaskID: String?
    @SceneStorage("desk.tab") private var storedTab: TaskTab?
    @SceneStorage("desk.dockPlacement") private var storedDockPlacement: DockPlacement?
    @SceneStorage("desk.dockOpen") private var storedDockOpen: Bool?

    init(ref: ProjectRef) {
        self.ref = ref
        let model = ProjectWindowModel(ref: ref, source: DataSources.make(for: ref))
        _model = State(initialValue: model)
        _terminals = State(initialValue: ShellTerminalRegistry(sessions: model.shellSessions))
        let agents = ShellTerminalRegistry(sessions: model.agentSessions)
        _agents = State(initialValue: agents)
        _auto = State(initialValue: AutoAgents(model: model, agents: agents))
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(DeskMetric.sidebarWidth)
        } detail: {
            ContentRouter(model: model)
        }
        .toolbar { ProjectToolbar(model: model) }
        .navigationTitle(model.snapshot?.project.name ?? ref.displayName)
        .navigationSubtitle(subtitle)
        .sheet(item: $model.sheet) { kind in
            SheetHost(model: model, kind: kind)
        }
        .modifier(DeskLinkRouting(model: model))
        .environment(\.shellTerminals, terminals)
        .environment(\.agentTerminals, agents)
        .focusedSceneValue(\.projectModel, model)
        .preferredColorScheme(SnapshotMode.shared.colorScheme ?? appearance.colorScheme)
        .frame(minWidth: 1100, minHeight: 720)
        .background { windowHooks }
        .task { await model.load() }
        .task { if !SnapshotMode.shared.isActive { await model.refresh(every: .seconds(120)) } }
        .onChange(of: model.snapshot != nil) { _, isLoaded in
            if isLoaded { applyFirstLoad() }
        }
        .onAppear { registry.windowOpened(ref) }
        .onDisappear { registry.windowClosed(ref) }
        .onChange(of: model.destination) { _, value in if layoutRestored { storedDestination = value } }
        .onChange(of: model.selectedTaskID) { _, value in if layoutRestored { storedTaskID = value ?? "" } }
        .onChange(of: model.tab) { _, value in if layoutRestored { storedTab = value } }
        .onChange(of: model.dockPlacement) { _, value in if layoutRestored { storedDockPlacement = value } }
        .onChange(of: model.dockOpen) { _, value in if layoutRestored { storedDockOpen = value } }
    }

    /// Snapshot mode's capture, ending the window's shells and agents when it closes, and its Auto loop.
    @ViewBuilder private var windowHooks: some View {
        SnapshotWindowHook(ref: ref, model: model)
        ShellLifetimeHook(registries: [terminals, agents])
        AutoAgentsHook(auto: auto, ref: ref)
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
        if let storedDockPlacement { model.dockPlacement = storedDockPlacement }
        if let storedDockOpen { model.dockOpen = storedDockOpen }
    }

    private func recordRecent() {
        guard case .local = ref, let project = model.snapshot?.project else { return }
        AppServices.recents.record(ref, name: project.name, displayPath: project.displayPath)
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
