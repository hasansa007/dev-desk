import AppKit
import DeskCore
import SwiftUI

/// The editor for `.devdesk/run.json`: the setup rows, then one card per run configuration. It edits a draft
/// and writes it back on a short debounce, so a save is never a keystroke and never a button either — the
/// file is the setting, and a pane you have to remember to save is a pane whose file says something else.
struct RunProjectPane: View {
    let model: ProjectWindowModel
    @State private var draft: ProjectRunPlan = .empty
    @State private var isLoaded = false
    @State private var pendingSave: Task<Void, Never>?
    @State private var saveError: String?
    @State private var confirmingReplace = false

    /// Long enough to absorb typing, short enough that switching sections or closing the dialog rarely has
    /// anything left to flush.
    private static let saveDelay: Duration = .milliseconds(600)

    private var runs: ProjectRuns { model.projectRuns }
    private var isSample: Bool { model.projectRoot == nil }
    /// A file the app could not read is never rewritten from a draft it never saw: editing waits until the
    /// user has chosen to replace it.
    private var isLocked: Bool { isSample || runs.readError != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader("Run project", scope: .thisProject,
                       summary: "The commands that start this project from the toolbar. Rows run in order in the same shell and stop at the first failure; there is no Save — a pause in typing writes the file.")
            // Only the EDITOR takes the lock. The notices and the footer used to take it too, under one
            // `.disabled(isLocked)` with a `.disabled(false)` that cannot undo it — which disabled "Replace
            // the file…", the one way out of the lock, and "Reveal in Finder", the other (2026-09-20).
            notices
            editor.disabled(isLocked)
            footer.padding(.top, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: load)
        // Reading on disk is the only other writer: a file edited by hand, or replaced, is picked up when
        // the pane is next shown, never while it is being typed into.
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear { flush() }
        .confirmationDialog("Replace \(ProjectRunFile.relativePath)?", isPresented: $confirmingReplace, titleVisibility: .visible) {
            Button("Replace with an empty plan", role: .destructive) { replaceFile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file could not be read, so what it holds is not shown here. Replacing it discards its contents; fix it by hand instead if they matter.")
        }
    }

    /// What is wrong, above the editor and outside its lock, because every action in here undoes the lock.
    @ViewBuilder private var notices: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSample {
                NoticeBanner(tone: .info, title: "", message: "A sample has no folder, so there is no run plan to edit or to run.", style: .callout)
                    .padding(.top, 16)
            } else if let reason = runs.readError {
                NoticeBanner(tone: .failed, title: "The run plan could not be read",
                             message: reason + " Nothing here is changed until you choose to replace the file.",
                             style: .callout) {
                    Button("Replace the file…") { confirmingReplace = true }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .smallWide))
                }
                .padding(.top, 16)
            }
            if let saveError {
                NoticeBanner(tone: .failed, title: "The file was not saved", message: saveError, style: .callout)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            setupCard.padding(.top, 18)

            SectionLabel("Run configurations").padding(.top, 22)
            if draft.configurations.isEmpty {
                emptyState.padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(draft.configurations) { configuration in
                        configurationCard(binding(for: configuration.id))
                    }
                }
                .padding(.top, 8)
                Button("Add configuration") { addConfiguration() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .padding(.top, 10)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Setup")
            SettingNote("Runs once, the first time Dev Desk runs this project in a folder — an install, usually. The toolbar's menu can run it again at any time.")
            CommandRows(rows: $draft.setup, placeholder: "cd web && npm install", addTitle: "Add command", onCommit: flush)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }

    // MARK: - Configurations

    private func configurationCard(_ configuration: Binding<ProjectRunConfiguration>) -> some View {
        let id = configuration.wrappedValue.id
        let isLive = runs.isRunning(configurationID: id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isLive { StatusDot(tone: .running, pulses: true) }
                TextField("Name", text: configuration.name)
                    .settingField(width: 260)
                    .onSubmit(flush)
                    .accessibilityLabel("Configuration name")
                Spacer(minLength: 4)
                if configuration.wrappedValue.isDefault {
                    PropertyChip("Default", tone: .info)
                        .help("The toolbar's play button runs this one")
                } else {
                    Button("Make default") { makeDefault(id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help("The toolbar's play button runs the default configuration")
                }
                Button { removeConfiguration(id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DeskColor.mutedInk)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A live run keeps its configuration: the stop rows are what stopping it types.
                .disabled(isLive)
                .help(isLive ? "Stop this run before removing its configuration" : "Remove this configuration")
                .accessibilityLabel("Remove \(configuration.wrappedValue.name)")
            }
            CommandRows(rows: configuration.commands, placeholder: "cd web && npm run dev", addTitle: "Add command", onCommit: flush)
            Rectangle().fill(DeskColor.rowDivider).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Stop")
                SettingNote("Runs before Dev Desk stops this run. With no rows, the run is interrupted (^C) and its shell ended.")
                CommandRows(rows: configuration.stop, placeholder: "docker compose down", addTitle: "Add stop command", onCommit: flush)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }

    private var emptyState: some View {
        NoticeBanner(tone: .info, title: "Nothing is configured yet",
                     message: "Add a configuration to run this project from the toolbar. When you would rather not write the commands by hand, `/dev:launch` is the family's door that detects and launches a project.",
                     style: .callout) {
            Button("Add configuration") { addConfiguration() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .smallWide))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(ProjectRunFile.relativePath)
                    .font(DeskFont.mono(12))
                    .foregroundStyle(DeskColor.ink)
                    .textSelection(.enabled)
                Button("Reveal in Finder") { reveal() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .disabled(isSample)
                    .help(isSample ? "A sample has no folder." : "Shows the file in Finder")
            }
            SettingNote("Committed with the project, so every clone and every worktree runs it the same way. Where setup has already run is Dev Desk's own note (`.devdesk/run-state.json`) and stays on this Mac.")
        }
        // The footer stays live under a lock: it says where the file is and opens it, which is exactly what a
        // pane locked by an unreadable file needs most.
    }

    // MARK: - Editing the draft

    /// A binding by id rather than by index: a card is removed while its fields are still on screen, and an
    /// index into a shorter array is how a delete becomes a crash.
    private func binding(for id: String) -> Binding<ProjectRunConfiguration> {
        Binding(get: { draft.configuration(id: id) ?? ProjectRunConfiguration(id: id, name: "") },
                set: { updated in
                    guard let index = draft.configurations.firstIndex(where: { $0.id == id }) else { return }
                    draft.configurations[index] = updated
                })
    }

    private func addConfiguration() {
        let number = draft.configurations.count + 1
        draft.configurations.append(ProjectRunConfiguration(name: "Configuration \(number)", commands: [""],
                                                            isDefault: draft.configurations.isEmpty))
    }

    private func removeConfiguration(_ id: String) {
        draft.configurations.removeAll { $0.id == id }
        // The default must not go with it; the next in line takes it, as a read of the file would decide.
        if !draft.configurations.contains(where: \.isDefault), !draft.configurations.isEmpty {
            draft.configurations[0].isDefault = true
        }
    }

    private func makeDefault(_ id: String) {
        for index in draft.configurations.indices {
            draft.configurations[index].isDefault = draft.configurations[index].id == id
        }
    }

    // MARK: - Reading and writing

    private func load() {
        runs.reload()
        draft = runs.plan
        isLoaded = true
    }

    /// Debounced: the write lands once typing pauses, and a burst of edits is one save.
    private func scheduleSave() {
        guard isLoaded, !isLocked else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Now, not later: a field committed with ⏎, or the pane going away, writes what is there.
    private func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    private func save() {
        guard isLoaded, !isLocked, draft.normalised() != runs.plan else { return }
        do {
            try runs.save(draft)
            saveError = nil
        } catch {
            saveError = Markdown.escape(error.localizedDescription)
        }
    }

    /// The one path that overwrites a file the app could not read, and it runs only from the dialog's own button.
    private func replaceFile() {
        do {
            try runs.save(.empty)
            draft = .empty
            saveError = nil
        } catch {
            saveError = Markdown.escape(error.localizedDescription)
        }
    }

    private func reveal() {
        guard let root = model.projectRoot else { return }
        let file = ProjectRunFile.url(in: root)
        let target = FileManager.default.fileExists(atPath: file.path) ? file : root
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

/// The command rows of one list — setup, a configuration's commands, its stop rows — each a monospace field
/// with its own ×, and an add button under them. The list is edited through the binding it was given, so the
/// pane's one draft is the only copy of the plan.
private struct CommandRows: View {
    @Binding var rows: [String]
    let placeholder: String
    let addTitle: String
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField(placeholder, text: row(index))
                        .settingField()
                        .onSubmit(onCommit)
                        .accessibilityLabel("Command \(index + 1)")
                    Button { remove(index) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DeskColor.mutedInk)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove this row")
                    .accessibilityLabel("Remove command \(index + 1)")
                }
            }
            Button(addTitle) { rows.append("") }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
    }

    /// Bounds-checked: a field whose row was just removed is still asked for its text once more before it goes.
    private func row(_ index: Int) -> Binding<String> {
        Binding(get: { index < rows.count ? rows[index] : "" },
                set: { if index < rows.count { rows[index] = $0 } })
    }

    private func remove(_ index: Int) {
        guard index < rows.count else { return }
        rows.remove(at: index)
    }
}
