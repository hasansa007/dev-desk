import DeskCore
import SwiftUI

struct AgentsDock: View {
    let model: ProjectWindowModel
    let task: DeskTask
    let dock: DockContent
    let placement: DockPlacement

    var body: some View {
        let edge = placement == .bottom ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        edge {
            paneRule
            VStack(spacing: 0) {
                bar
                Rectangle()
                    .fill(DeskColor.terminalPaneBorder)
                    .frame(height: 1)
                panes
            }
        }
        .background(DeskColor.terminalGround)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agents & Terminals")
    }

    private var selectedTab: DockTab? {
        dock.tabs.first { $0.id == model.dockTabID } ?? dock.tabs.first
    }

    private var canSplit: Bool {
        guard let id = dock.splitTabID else { return false }
        return dock.tabs.contains { $0.id == id }
    }

    private var splitTab: DockTab? {
        guard model.dockSplit, let id = dock.splitTabID else { return nil }
        return dock.tabs.first { $0.id == id }
    }

    private var primaryTab: DockTab? {
        guard let splitTab, selectedTab?.id == splitTab.id else { return selectedTab }
        return dock.tabs.first { $0.id != splitTab.id }
    }

    private var paneRule: some View {
        Rectangle()
            .fill(DeskColor.terminalPaneBorder)
            .frame(width: placement == .side ? 1 : nil, height: placement == .bottom ? 1 : nil)
    }

    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                tabStrip
                Spacer(minLength: 0)
                caption
                    .lineLimit(1)
                controls
            }
            .frame(height: 33)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        tabStrip
                            .frame(maxHeight: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    controls
                }
                .frame(height: 33)
                caption
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.terminalBar)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(dock.tabs) { tab in
                TaskDockTabButton(title: tab.title, isSelected: tab.id == selectedTab?.id) { model.dockTabID = tab.id }
            }
        }
        .fixedSize()
    }

    private var caption: some View {
        Text(dock.caption)
            .font(.system(size: 11))
            .foregroundStyle(DeskColor.terminalDim)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(splitTab == nil ? "Split panes" : "Single pane") { model.toggleSplit() }
                .disabled(!canSplit)
                .help(canSplit ? "Show a second view of this session alongside the first" : "This task has no second session view to split")
            Button("Hide") { model.toggleDock() }
                .help("Hide the Agents & Terminals dock")
        }
        .buttonStyle(TaskDockControlStyle())
        .fixedSize()
    }

    @ViewBuilder private var panes: some View {
        let layout = placement == .bottom ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            if let primaryTab {
                pane(primaryTab)
            }
            if let splitTab {
                if primaryTab != nil {
                    Rectangle()
                        .fill(DeskColor.terminalPaneBorder)
                        .frame(width: placement == .bottom ? 1 : nil, height: placement == .side ? 1 : nil)
                }
                pane(splitTab)
            }
        }
    }

    private func pane(_ tab: DockTab) -> some View {
        paneContent(tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tab.id)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tab.title)
    }

    @ViewBuilder private func paneContent(_ tab: DockTab) -> some View {
        switch tab.kind {
        case .transcript(let transcript):
            TerminalTranscriptView(transcript: transcript)
        case .liveShell:
            ShellPane(sessions: model.shellSessions, task: task)
        case .unavailable(let reason):
            DockMessage(text: reason)
        }
    }
}

/// The Shell tab. Nothing runs until Start shell is clicked, and the shell belongs to the window's registry, so it outlives this pane.
private struct ShellPane: View {
    let sessions: ShellSessions
    let task: DeskTask
    @Environment(\.shellTerminals) private var terminals
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"

    private static let trustNote = "Starting a shell runs your login shell and git in this repository, as Terminal would. Only start one in a repository you trust."

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeskColor.terminalGround)
            .task(id: task.id) { await refreshPlan() }
    }

    @ViewBuilder private var content: some View {
        switch sessions.state(for: task.id) {
        case .idle(let plan):
            DockMessage(text: Self.trustNote, detail: plan.map(Self.planLine)) {
                Button("Start shell") { start() }
                    .disabled(terminals == nil)
            }
        case .preparing:
            DockMessage(text: "Preparing the task's folder…")
        case .running(let folder):
            VStack(spacing: 0) {
                runningBar(note: folder.note)
                if let terminals {
                    ShellTerminalView(terminals: terminals, taskID: task.id)
                }
            }
        case .ended(_, let status):
            DockMessage(text: status.map { "Shell ended (status \($0))." } ?? "Shell ended.") {
                Button("Start again") { start() }
                    .disabled(terminals == nil)
            }
        case .failed(let message):
            DockMessage(text: message)
        }
    }

    private func runningBar(note: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let note {
                    Text(verbatim: note)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.terminalDim2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(note)
                }
                Spacer(minLength: 0)
                Button("End shell") { terminals?.end(taskID: task.id) }
                    .buttonStyle(TaskDockControlStyle())
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(DeskColor.terminalBar)
            Rectangle()
                .fill(DeskColor.terminalPaneBorder)
                .frame(height: 1)
        }
    }

    /// The values are taken at the click, and the shell starts once the folder is ready even if the user has moved to another task by then.
    private func start() {
        guard let terminals else { return }
        let taskID = task.id
        let branch = task.branch
        let taskNumber = task.taskNumber
        let noBranchNote = task.noBranchNote
        let location = worktreeLocation
        Task {
            await sessions.start(taskID: taskID, branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote, worktreeLocation: location)
            guard case .running(let folder) = sessions.state(for: taskID) else { return }
            terminals.start(taskID: taskID, folder: folder.url)
        }
    }

    /// Asking git for its worktrees is read-only; a tab past idle keeps the folder it already has.
    private func refreshPlan() async {
        guard case .idle = sessions.state(for: task.id) else { return }
        await sessions.refreshPlan(taskID: task.id, branch: task.branch, taskNumber: task.taskNumber,
                                   noBranchNote: task.noBranchNote, worktreeLocation: worktreeLocation)
    }

    private static func planLine(_ plan: TaskFolderPlan) -> String {
        switch plan {
        case .existing(let folder, let branch):
            return "Opens in \(display(folder)), where \(branch) is checked out."
        case .create(let path, let branch):
            return "Creates a worktree for \(branch) at \(display(path))."
        case .root(_, let note):
            // The task-folder notes already end in a full stop.
            return "Opens at the project root: \(note.hasSuffix(".") ? String(note.dropLast()) : note)."
        }
    }

    private static func display(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// Plain text only: reasons, notes, branches and paths come from the repository, so none of them is rendered as markdown.
private struct DockMessage<Actions: View>: View {
    let text: String
    let detail: String?
    let actions: Actions

    init(text: String, detail: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.text = text
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: text)
                    .foregroundStyle(DeskColor.terminalInk)
                if let detail {
                    Text(verbatim: detail)
                        .foregroundStyle(DeskColor.terminalDim2)
                }
                if Actions.self != EmptyView.self {
                    actions
                        .buttonStyle(TaskDockControlStyle())
                        .fixedSize()
                        .padding(.top, 4)
                }
            }
            .font(DeskFont.secondary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }
}

extension DockMessage where Actions == EmptyView {
    init(text: String, detail: String? = nil) {
        self.init(text: text, detail: detail) { EmptyView() }
    }
}

private struct TaskDockTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        Button(action: action) {
            Text(title)
                .font(DeskFont.small)
                .foregroundStyle(isSelected ? Color.white : DeskColor.terminalDim2)
                .lineLimit(1)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(isSelected ? DeskColor.accent : Color.clear, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TaskDockControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TaskDockControlBody(configuration: configuration)
    }
}

private struct TaskDockControlBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(DeskColor.terminalInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(DeskColor.terminalControlFill, in: shape)
            .overlay(shape.strokeBorder(DeskColor.terminalControlBorder))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
    }
}
