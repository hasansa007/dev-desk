import DeskCore
import SwiftUI

struct DeskCommands: Commands {
    @FocusedValue(\.projectModel) private var model: ProjectWindowModel?
    @Environment(\.openWindow) private var openWindow

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
                Button("Focus") { model?.setMode(.focus) }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                Button("Parallel") { model?.setMode(.parallel) }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                Divider()
                Button("Reload") { reload() }
                    .keyboardShortcut("r")
                Button("Ask About This Project") { model?.toggleInsights() }
                    .keyboardShortcut("i", modifiers: [.shift, .command])
                Button("Show Agents Dock") { model?.toggleDock() }
                    .keyboardShortcut("d", modifiers: [.option, .command])
            }
            .disabled(model == nil)
        }
    }

    private func reload() {
        guard let model else { return }
        Task { await model.load() }
    }
}
