import AppKit
import DeskCore
import SwiftUI

/// The one window (ADR 0050). The strip down its left edge, and beside it either Home or the project you
/// selected. Every OTHER open project is still here too — as hooks with no size, loading, running and
/// reporting — because the strip's promise is that a project you are not looking at can still need you.
struct WorkspaceWindow: View {
    @State private var workspace = Workspace.shared
    @Environment(OpenProjectRegistry.self) private var registry

    var body: some View {
        HStack(spacing: 0) {
            ProjectStrip(workspace: workspace)
            Group {
                if let context = workspace.selected {
                    ProjectHost(context: context)
                        // A project is one place: rebuilding the host on a switch is what keeps the sidebar,
                        // the toolbar and the sheet belonging to the project you are actually looking at.
                        .id(context.id)
                } else {
                    HomeScreen(workspace: workspace)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: DeskMetric.windowMinWidth + DeskMetric.stripWidth, minHeight: DeskMetric.windowMinHeight)
        .background { hooks }
        .sheet(isPresented: $workspace.isOpeningProject) {
            LauncherView(context: .sheet, onDismiss: { workspace.isOpeningProject = false })
        }
        // ⌘, with no project: the same Settings dialog holding only what is not a project's.
        .sheet(isPresented: $workspace.isShowingSettings) {
            AppSettingsSheet(onClose: { workspace.isShowingSettings = false })
        }
        // The title bar is navigation: macOS painted its own grey there, a fourth one beside the sidebar.
        // On the window, not on the project: Home was left with the system's own light bar, and a shorter
        // one, so switching to it changed the height of the window's chrome (2026-09-20, on screen).
        // It takes the STRIP's ground, not the rail's: the strip runs up to the title bar, and two near
        // greys meeting at the window's rounded corner drew a seam across it. One ground, one corner.
        .toolbarBackground(DeskColor.strip, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .modifier(AppliesAppearance(override: SnapshotMode.shared.colorScheme))
        .background { WindowChrome() }
        .onAppear { workspace.attach(registry: registry) }
    }

    /// No size, and never rebuilt by a project switch: this is where every open project lives whether or not
    /// it is on screen. `ShellLifetimeHook` is the window's, not a project's — closing the window still ends
    /// every session in it, the way closing a project window used to.
    @ViewBuilder private var hooks: some View {
        let contexts = workspace.contextsInStripOrder
        ForEach(contexts) { context in
            ProjectHooks(context: context, workspace: workspace)
        }
        ShellLifetimeHook(registries: contexts.map(\.terminals))
    }
}

/// One project's life, running whether or not that project is the one on screen: its loads, its Auto loop, its
/// queue drain, the cards it closes when they reach Done, and the place it remembers being.
struct ProjectHooks: View {
    let context: ProjectContext
    let workspace: Workspace
    @AppStorage(PreferenceKey.autoReload) private var autoReload = false

    private var model: ProjectWindowModel { context.model }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background {
                SnapshotWindowHook(ref: context.ref, model: model)
                AutoAgentsHook(auto: context.auto, ref: context.ref)
                StartQueueHook(queue: context.queue)
                FiledWorkHook(model: model)
            }
            .task { await model.sync() }
            // Restarted by the toggle: turning it off cancels the loop, turning it on starts a fresh one.
            .task(id: autoReload) {
                if autoReload, !SnapshotMode.shared.isActive {
                    await model.refresh(every: .seconds(ProjectWindowModel.refreshSeconds))
                }
            }
            .onChange(of: model.snapshot != nil) { _, isLoaded in
                if isLoaded { context.applyFirstLoad() }
            }
            .onChange(of: model.doneTaskIDs) { old, new in
                // The first load is not an arrival: every merged card would look new.
                guard !old.isEmpty else { return }
                model.closingOnDone.formUnion(model.liveSessions(ofDone: new.subtracting(old)))
                context.closeDone()
            }
            .onChange(of: model.destination) { _, _ in context.rememberFocus() }
            .onChange(of: model.selectedTaskID) { _, _ in context.rememberFocus() }
            .onChange(of: model.tab) { _, _ in context.rememberFocus() }
            .onReceive(NotificationCenter.default.publisher(for: RunNotifications.openSession)) { note in
                guard case .local(let path) = context.ref, note.userInfo?["directory"] as? String == path else { return }
                // The session is in THIS project, which may not be the one in front: answering a notification
                // has to switch projects, or it lands you on the right tab of the wrong project.
                workspace.select(context.ref)
                if let session = note.userInfo?["session"] as? String { model.selectedSessionID = session }
                model.go(.terminals)
            }
    }
}

/// The title bar, made to belong to the window. `toolbarBackground` tints the bar macOS 15 draws; on macOS 26
/// the toolbar is glass and paints its own pale material over the tint, so the bar read as a light strip
/// across the top of a near-black app (2026-09-20, on screen). Transparent titlebar plus the window's own
/// ground is the one thing both versions honour.
private struct WindowChrome: View {
    var body: some View {
        WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(DeskColor.strip)
        }
        .frame(width: 0, height: 0)
    }
}
