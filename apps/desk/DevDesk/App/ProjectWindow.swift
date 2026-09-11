import DeskCore
import SwiftUI

struct ProjectWindow: View {
    let ref: ProjectRef
    @State private var model: ProjectWindowModel
    @Environment(OpenProjectRegistry.self) private var registry
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    @SceneStorage("desk.destination") private var storedDestination: Destination?
    @SceneStorage("desk.taskID") private var storedTaskID: String?
    @SceneStorage("desk.tab") private var storedTab: TaskTab?
    @SceneStorage("desk.dockPlacement") private var storedDockPlacement: DockPlacement?
    @SceneStorage("desk.dockOpen") private var storedDockOpen: Bool?

    init(ref: ProjectRef) {
        self.ref = ref
        _model = State(initialValue: ProjectWindowModel(ref: ref, source: DataSources.make(for: ref)))
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
        .environment(\.openURL, OpenURLAction { url in
            guard let link = DeskLink(url: url) else { return .systemAction }
            model.handle(link)
            return .handled
        })
        .focusedSceneValue(\.projectModel, model)
        .preferredColorScheme(appearance.colorScheme)
        .frame(minWidth: 1100, minHeight: 720)
        .task {
            await model.load()
            restoreLayout()
            recordRecent()
        }
        .onAppear { registry.windowOpened(ref) }
        .onDisappear { registry.windowClosed(ref) }
        .onChange(of: model.destination) { _, value in storedDestination = value }
        .onChange(of: model.selectedTaskID) { _, value in storedTaskID = value ?? "" }
        .onChange(of: model.tab) { _, value in storedTab = value }
        .onChange(of: model.dockPlacement) { _, value in storedDockPlacement = value }
        .onChange(of: model.dockOpen) { _, value in storedDockOpen = value }
    }

    private var subtitle: String {
        guard let project = model.snapshot?.project, !project.branch.isEmpty else { return "" }
        return "\(project.displayPath) · \(project.branch)"
    }

    /// An empty stored task id means the board was showing no task; an id that no longer exists is ignored.
    private func restoreLayout() {
        guard model.snapshot != nil else { return }
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

extension ProjectRef {
    var displayName: String {
        switch self {
        case .sample(let project): return project.title
        case .local(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}
