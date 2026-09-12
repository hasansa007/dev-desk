import AppKit
import DeskCore
import SwiftUI

struct CloneRepositorySheet: View {
    var onDismiss: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var urlText = ""
    @State private var destination = Self.defaultDestination()
    @State private var isCloning = false
    @State private var errorMessage: String?
    @State private var cloneTask: Task<Void, Never>?

    var body: some View {
        SheetChrome(title: "Clone repository", confirmTitle: "Clone",                     confirmDisabled: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCloning,
                    cancelHelp: isCloning ? "Stops waiting; a clone already under way may still finish in the chosen folder." : nil,
                    onCancel: cancel, onConfirm: { cloneTask = Task { await clone() } }) {
            VStack(alignment: .leading, spacing: 14) {
                row("Repository URL") {
                    TextField("https://github.com/org/repo.git", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                }
                row("Destination") {
                    HStack(spacing: 8) {
                        Text(destination.path)
                            .font(DeskFont.mono(12))
                            .foregroundStyle(DeskColor.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…") { chooseDestination() }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                }
                if isCloning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Cloning…").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.tone(.failed).foreground)
                }
            }
        }
        .onDisappear { cloneTask?.cancel() }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label).foregroundStyle(DeskColor.secondaryInk).frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
    }

    private func cancel() {
        cloneTask?.cancel()
        onDismiss()
    }

    /// A cancelled wait never opens a window, even when the clone itself finishes afterwards.
    private func clone() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCloning = true
        errorMessage = nil
        do {
            let path = try await ProjectOperations.cloneRepository(url: trimmed, into: destination)
            guard !Task.isCancelled else { return }
            isCloning = false
            openWindow(value: ProjectRef.local(path: path.path))
            onDismiss()
        } catch {
            guard !Task.isCancelled else { return }
            isCloning = false
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultDestination() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let code = home.appendingPathComponent("code")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: code.path, isDirectory: &isDirectory), isDirectory.boolValue { return code }
        return home
    }
}

struct CloneRepositorySheet_Previews: PreviewProvider {
    static var previews: some View {
        CloneRepositorySheet(onDismiss: {})
            .frame(width: 720)
    }
}
