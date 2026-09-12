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
                Button("Reload") { reload() }
                    .keyboardShortcut("r")
            }
            .disabled(model == nil)
        }
    }

    private func reload() {
        guard let model else { return }
        Task { await model.load() }
    }
}
