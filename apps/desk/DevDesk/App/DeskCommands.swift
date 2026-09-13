import DeskCore
import SwiftUI

struct DeskCommands: Commands {
    @FocusedValue(\.projectModel) private var model: ProjectWindowModel?
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project…") { openWindow(id: "launcher") }
                .keyboardShortcut("o")
        }
        CommandMenu("Project") {
            Group {
                ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, destination in
                    Button(destination.title) { model?.go(destination) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Divider()
                // The card has had a Start button since the gaps epic; what it had no way to do was start
                // from the keyboard. The menu is also where a shortcut is discovered.
                Button("Start Task") { startTask() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(startableTask == nil)
                Button("New Terminal") { newTerminal() }
                    .keyboardShortcut("t")
                Divider()
                Button("Reload") { reload() }
                    .keyboardShortcut("r")
            }
            .disabled(model == nil)
        }
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
        model.newTerminal()
        model.go(.terminals)
    }

    private func reload() {
        guard let model else { return }
        Task { await model.load() }
    }
}
