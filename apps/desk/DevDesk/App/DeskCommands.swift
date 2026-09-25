import DeskCore
import SwiftUI

struct DeskCommands: Commands {
    /// The project the strip has selected — NOT `@FocusedValue`. With one window (ADR 0050) the workspace is
    /// the authority on which project you are in, and the focused value depended on the split view that the
    /// rail replaced: with it gone nothing published the model, so every item in this menu, ⇧⌘S included,
    /// was permanently disabled (2026-09-20, reported as "compact sidebar is not functional").
    @State private var workspace = Workspace.shared

    private var model: ProjectWindowModel? { workspace.selected?.model }
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    /// A narrow window takes the rail whatever this says; this is the choice at widths that have room.
    @AppStorage(PreferenceKey.sidebarRail) private var railMode = false

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            // Never disabled: ⌘, on Home opens the settings that are not a project's (2026-09-20). It used
            // to need a project, so the one screen with no project had no way into Settings at all.
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            // One window now (ADR 0050): Open project is the strip's `+`, raised as a dialog over it.
            Button("Open Project…") { Workspace.shared.isOpeningProject = true }
                .keyboardShortcut("o")
        }
        // ⌘1…⌘9 are the strip's projects, as they are a browser's tabs (#96). In Window rather than Project, which
        // is disabled on Home — the one screen a project is most often switched to from.
        CommandGroup(before: .windowArrangement) {
            ForEach(Array(workspace.contextsInStripOrder.prefix(9).enumerated()), id: \.element.id) { index, context in
                Button(context.name) { workspace.select(context.ref) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
        }
        CommandMenu("Project") {
            Group {
                ForEach(Destination.sidebar, id: \.self) { destination in
                    Button(destination.title) { model?.go(destination) }
                        .keyboardShortcut(KeyEquivalent(destination.key))
                }
                Divider()
                // The card has had a Start button since the gaps epic; what it had no way to do was start
                // from the keyboard. The menu is also where a shortcut is discovered.
                Button("Start Task") { startTask() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(startableTask == nil)
                Button("New Terminal") { newTerminal() }
                    .keyboardShortcut("t")
                // Safari's and Xcode's keys for the tab beside this one. Only where sessions are on screen — the
                // Sessions tab, or the dock opened on any other — since a step through sessions you cannot see
                // would change what the dock shows behind your back.
                Button("Next Session") { model?.sessionStep = SessionStepRequest(1) }
                    .keyboardShortcut("]")
                    .disabled(!showsSessions)
                Button("Previous Session") { model?.sessionStep = SessionStepRequest(-1) }
                    .keyboardShortcut("[")
                    .disabled(!showsSessions)
                Toggle("Compact Sidebar", isOn: $railMode)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                // Xcode's keys: ⌘R runs, ⌘. stops. Pulling moved to ⇧⌘R.
                Button("Run") { model?.windowCommand = WindowCommandRequest(.run) }
                    .keyboardShortcut("r")
                Button("Stop Run") { model?.windowCommand = WindowCommandRequest(.stop) }
                    .keyboardShortcut(".")
                    .disabled(model?.projectRuns.isAnythingRunning != true)
                Button("Pull and Reload") { reload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Settings…") { openSettings() }
                Divider()
                // ⌘W closes the window, which is the whole app now (ADR 0050); this takes one project off
                // the strip. Right-click does it too, on the strip icon and on the Home card.
                Button("Close Project") { closeProject() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            .disabled(model == nil)
        }
    }

    private var showsSessions: Bool {
        guard let model, case .loaded = model.loadState else { return false }
        return model.destination == .terminals || SessionDockState.shared.isOpen(model.ref)
    }

    private func closeProject() {
        guard let ref = workspace.selection else { return }
        workspace.close(ref)
    }

    /// The card the board is standing on, when it is one that can be started and has nothing running.
    private var startableTask: DeskTask? {
        guard let model, let id = model.selectedTaskID ?? model.lastOpenedTaskID,
              let task = model.task(id), task.column != .done,
              model.activity(of: task) == nil,
              model.startBlockedReason(for: task, agent: defaultConnection) == nil else { return nil }
        return task
    }

    private func startTask() {
        guard let model, let task = startableTask else { return }
        model.startTask(task, agent: defaultConnection)
    }

    private func newTerminal() {
        guard let model, model.sessions.startRefusal(for: .shell) == nil else { return }
        // The same start the "+" makes: a row alone is a terminal with no shell behind it.
        model.terminalAwaitingStart = model.newTerminal()
        model.go(.terminals)
    }

    private func reload() {
        guard let model else { return }
        Task { await model.sync() }
    }

    /// A project's Settings opens over that project; on Home the workspace raises the app-wide ones.
    private func openSettings() {
        if let model { model.present(.settings) } else { Workspace.shared.isShowingSettings = true }
    }
}
