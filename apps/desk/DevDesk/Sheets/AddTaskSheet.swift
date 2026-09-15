import DeskCore
import SwiftUI

/// A task typed straight onto the board. Adding it writes a file into `docs/backlog/` (ADR 0027) — instant
/// and local, no agent run, even when the project has a tracker; the card's own menu files it on GitHub
/// later, when that is a decision worth making. A refused write keeps the sheet open: the title just typed
/// must not vanish with the failure, which the window's banner explains.
struct AddTaskSheet: View {
    let model: ProjectWindowModel
    let column: BoardColumn

    @State private var title = ""
    @State private var notes = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        SheetChrome(title: "Add a task to \(column.title)", confirmTitle: "Add task",
                    confirmDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onCancel: model.dismissSheet, onConfirm: confirm) {
            VStack(alignment: .leading, spacing: 14) {
                row("Title") {
                    TextField("What needs doing", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                }
                row("Notes") {
                    TextField("What it is, in your own words — optional", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...8)
                }
                Text("This becomes a file in docs/backlog/. Dev Desk writes it and never commits it, and the card's menu can file it on GitHub later.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .padding(.top, 2)
            }
        }
        .onAppear { titleFocused = true }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).foregroundStyle(DeskColor.secondaryInk).frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func confirm() {
        Task { if await model.addTask(title: title, notes: notes, column: column) { model.dismissSheet() } }
    }
}
