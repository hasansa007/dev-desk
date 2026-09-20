import AppKit
import DeskCore
import SwiftUI

struct CreateProjectSheet: View {
    var onDismiss: () -> Void

    @State private var name = ""
    @State private var parent = Self.defaultParent()
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createTask: Task<Void, Never>?

    var body: some View {
        SheetChrome(title: "Create new project", confirmTitle: "Create",                     confirmDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating,
                    onCancel: cancel, onConfirm: { createTask = Task { await create() } }) {
            VStack(alignment: .leading, spacing: 14) {
                row("Project name") {
                    TextField("my-project", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                row("Parent folder") {
                    HStack(spacing: 8) {
                        Text(parent.path)
                            .font(DeskFont.mono(12))
                            .foregroundStyle(DeskColor.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…") { chooseParent() }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                }
                if isCreating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Creating…").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.tone(.failed).foreground)
                }
            }
        }
        .onDisappear { createTask?.cancel() }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label).foregroundStyle(DeskColor.secondaryInk).frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parent = url
    }

    private func cancel() {
        createTask?.cancel()
        onDismiss()
    }

    /// A cancelled wait never opens a window, even when the folder is created afterwards.
    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        do {
            let path = try await ProjectOperations.createProject(named: trimmed, in: parent)
            guard !Task.isCancelled else { return }
            isCreating = false
            Workspace.shared.open(.local(path: path.path))
            onDismiss()
        } catch {
            guard !Task.isCancelled else { return }
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultParent() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let code = home.appendingPathComponent("code")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: code.path, isDirectory: &isDirectory), isDirectory.boolValue { return code }
        return home
    }
}

struct CreateProjectSheet_Previews: PreviewProvider {
    static var previews: some View {
        CreateProjectSheet(onDismiss: {})
            .deskSheetWidth(720)
    }
}
