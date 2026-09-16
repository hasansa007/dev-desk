import AppKit
import DeskCore
import SwiftUI
import UniformTypeIdentifiers

/// The developer's "Start with" list as the start sheet and a card's menu offer it. An app that has moved is still
/// listed, disabled, with the reason: a list that silently drops an entry looks like the entry was never saved.
enum StartWithRows {
    static func isAvailable(_ entry: StartWithEntry) -> Bool {
        if case .app(let path) = entry.kind { return FileManager.default.fileExists(atPath: path) }
        return true
    }

    static func options(_ entries: [StartWithEntry]) -> [RunnerOption] {
        entries.map {
            RunnerOption(id: $0.id, name: $0.name, detail: isAvailable($0) ? $0.detail : "app not found",
                         kind: .handoff, isAvailable: isAvailable($0))
        }
    }
}

/// Settings › Start with: the other apps a task can start with (ADR 0036 decision 6, widened to a list the developer
/// keeps). Stored for every project under one preference key.
struct StartWithPane: View {
    @AppStorage(PreferenceKey.startWith) private var data = Data()
    @State private var commandName = ""
    @State private var commandTemplate = ""

    private var entries: [StartWithEntry] { StartWithList.decode(data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Start with", scope: .everyProject)
            Text("Other apps a task can start with, from the start sheet and a card's ⋯ menu. An app opens the project folder, and the task's prompt is copied to the clipboard so you can paste it there. A command runs in a Sessions terminal with the task filled in.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                if entries.isEmpty {
                    Text("Nothing added yet.")
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.faintInk)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, at: index)
                }
            }
            .padding(.top, 16)

            Button("Add an app…", action: addApp)
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .padding(.top, 14)

            SectionLabel("Add a command")
                .padding(.top, 22)
            HStack(spacing: 8) {
                field("Name", text: $commandName, width: 140)
                field("zadloop run {folder} --prompt {prompt}", text: $commandTemplate, width: 380)
                Button("Add", action: addCommand)
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .disabled(commandName.trimmed.isEmpty || commandTemplate.trimmed.isEmpty)
            }
            .padding(.top, 8)
            Text(commandHelp)
                .font(DeskFont.secondary)
                .foregroundStyle(unknownInDraft.isEmpty ? DeskColor.mutedInk : DeskColor.tone(.failed).dot)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 8)
        }
    }

    /// Placeholders are quoted as they are filled, so the one mistake worth catching early is a name that isn't one.
    private var unknownInDraft: [String] { StartWithTemplate.unknownPlaceholders(in: commandTemplate) }

    private var commandHelp: String {
        guard unknownInDraft.isEmpty else {
            return "Not a placeholder: " + unknownInDraft.map { "{\($0)}" }.joined(separator: ", ")
                + ". It would be typed as written."
        }
        return "Placeholders: " + StartWithTemplate.placeholders.map { "{\($0)}" }.joined(separator: " ")
            + ". Each is quoted for you, so don't put quotes around it."
    }

    private func row(_ entry: StartWithEntry, at index: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundStyle(DeskColor.ink)
                Text(summary(entry))
                    .font(DeskFont.mono(11))
                    .foregroundStyle(problem(entry) == nil ? DeskColor.mutedInk : DeskColor.tone(.failed).dot)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(problem(entry) ?? summary(entry))
            }
            Spacer(minLength: 8)
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .disabled(index == 0)
                .accessibilityLabel("Move \(entry.name) up")
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .disabled(index == entries.count - 1)
                .accessibilityLabel("Move \(entry.name) down")
            Button("Remove") { remove(entry) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: 700, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.border))
    }

    private func summary(_ entry: StartWithEntry) -> String {
        switch entry.kind {
        case .app(let path): return path
        case .command(let template): return template
        }
    }

    private func problem(_ entry: StartWithEntry) -> String? {
        switch entry.kind {
        case .app(let path):
            return StartWithRows.isAvailable(entry) ? nil : "No app at \(path) any more."
        case .command(let template):
            let unknown = StartWithTemplate.unknownPlaceholders(in: template)
            return unknown.isEmpty ? nil : "Not a placeholder: " + unknown.map { "{\($0)}" }.joined(separator: ", ")
        }
    }

    private func field(_ prompt: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(width: width, height: 28)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
    }

    private func save(_ list: [StartWithEntry]) { data = StartWithList.encode(list) }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
        save(entries + [StartWithEntry(name: name, kind: .app(path: url.path))])
    }

    private func addCommand() {
        save(entries + [StartWithEntry(name: commandName.trimmed, kind: .command(template: commandTemplate.trimmed))])
        commandName = ""
        commandTemplate = ""
    }

    private func remove(_ entry: StartWithEntry) { save(entries.filter { $0.id != entry.id }) }

    private func move(_ index: Int, by offset: Int) {
        var list = entries
        let target = index + offset
        guard list.indices.contains(index), list.indices.contains(target) else { return }
        list.swapAt(index, target)
        save(list)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
