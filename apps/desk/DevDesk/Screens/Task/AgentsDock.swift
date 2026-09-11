import AppKit
import DeskCore
import SwiftUI

struct AgentsDock: View {
    let model: ProjectWindowModel
    let task: DeskTask
    let dock: DockContent
    let placement: DockPlacement
    /// A sample's transcript tabs the user has clicked, or clicked into; each then says it is a recording.
    @State private var recordingNoticeTabIDs: Set<String> = []

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
                TaskDockTabButton(title: tab.title, isSelected: tab.id == selectedTab?.id) {
                    model.dockTabID = tab.id
                    noteRecording(tab)
                }
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
            if model.ref.isSample {
                SampleRecordingPane(transcript: transcript, showsNotice: recordingNoticeTabIDs.contains(tab.id)) { noteRecording(tab) }
            } else {
                TerminalTranscriptView(transcript: transcript)
            }
        case .liveShell:
            ShellPane(sessions: model.shellSessions, task: task)
        case .liveAgent:
            AgentPane(model: model, task: task)
        case .unavailable(let reason):
            DockMessage(text: reason)
        }
    }

    private func noteRecording(_ tab: DockTab) {
        guard model.ref.isSample, tab.transcript != nil else { return }
        recordingNoticeTabIDs.insert(tab.id)
    }
}

/// A sample's transcript looks like a live terminal, cursor and all, but takes no input; a click on it, or on its tab, says so.
private struct SampleRecordingPane: View {
    static let note = "This terminal is a recording in the sample project. Open a real folder with ⌘O to get a live shell here."

    let transcript: TerminalTranscript
    let showsNotice: Bool
    let onClick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsNotice {
                Text(verbatim: Self.note)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.terminalDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(DeskColor.terminalBar)
                Rectangle()
                    .fill(DeskColor.terminalPaneBorder)
                    .frame(height: 1)
            }
            TerminalTranscriptView(transcript: transcript, help: Self.note)
                .background { ClickSensor(onClick: onClick) }
        }
        .help(Self.note)
    }
}

/// Runs `onClick` for a click anywhere over it without taking the click, so the recording keeps its own text selection and scrolling.
/// A local monitor sees the app's events before any view does.
private struct ClickSensor: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> ClickSensorView { ClickSensorView() }
    func updateNSView(_ view: ClickSensorView, context: Context) { view.onClick = onClick }
}

private final class ClickSensorView: NSView {
    var onClick: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = window == nil ? nil : NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
            return event
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
            DockMessage(text: Self.trustNote, detail: plan.map(TaskFolderText.planLine)) {
                Button("Start shell") { start() }
                    .disabled(terminals == nil)
            }
        case .preparing:
            DockMessage(text: "Preparing the task's folder…")
        case .running(let folder):
            VStack(spacing: 0) {
                DockRunningBar(note: folder.note, stopTitle: "End shell") { terminals?.end(taskID: task.id) }
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
}

/// The Agents tab: Claude Code or Codex in the task's folder. Nothing runs until Start agent is clicked or Auto starts it,
/// and the agent belongs to the window's agent registry, so it outlives this pane.
private struct AgentPane: View {
    let model: ProjectWindowModel
    let task: DeskTask
    @Environment(\.agentTerminals) private var agents
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @AppStorage private var connectionOverride: String

    init(model: ProjectWindowModel, task: DeskTask) {
        self.model = model
        self.task = task
        _connectionOverride = AppStorage(wrappedValue: "", PreferenceKey.connectionOverride(model.ref))
    }

    private var sessions: ShellSessions { model.agentSessions }

    private var choice: AgentChoice {
        AgentChoice.resolve(override: connectionOverride, defaultConnection: defaultConnection, connections: model.snapshot?.connections ?? [])
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeskColor.terminalGround)
            .task(id: task.id) { await refreshPlan() }
    }

    @ViewBuilder private var content: some View {
        switch sessions.state(for: task.id) {
        case .idle(let plan):
            switch choice {
            case .ready(let agent):
                DockMessage(text: Self.startNote(agent), detail: plan.map(TaskFolderText.planLine)) {
                    Button("Start agent") { start(agent) }
                        .disabled(agents == nil)
                }
            case .unavailable(let reason):
                DockMessage(text: reason)
            }
        case .preparing:
            DockMessage(text: "Preparing the task's folder…")
        case .running(let folder):
            VStack(spacing: 0) {
                DockRunningBar(note: folder.note, stopTitle: "Stop agent") { agents?.end(taskID: task.id) }
                if let agents {
                    ShellTerminalView(terminals: agents, taskID: task.id)
                }
            }
        case .ended(let folder, let status):
            startable(status.map { "Agent ended (status \($0))." } ?? "Agent ended.", detail: folder.note, button: "Start again")
        case .failed(let message):
            // Auto won't run an agent at the project root, so its start fails here with the folder's note; starting by hand may run it there.
            if model.ref.isSample {
                DockMessage(text: message)
            } else {
                startable(message, detail: nil, button: "Start agent")
            }
        }
    }

    /// The message with the start button, or with the reason the agent can't start.
    @ViewBuilder private func startable(_ text: String, detail: String?, button: String) -> some View {
        switch choice {
        case .ready(let agent):
            DockMessage(text: text, detail: detail) {
                Button(button) { start(agent) }
                    .disabled(agents == nil)
            }
        case .unavailable(let reason):
            DockMessage(text: text, detail: reason)
        }
    }

    /// The agent starts once the folder is ready, even if the user has moved to another task by then.
    private func start(_ agent: AgentKind) {
        agents?.startAgent(for: task, agent: agent, worktreeLocation: worktreeLocation)
    }

    /// Read-only, as the Shell tab's; a tab past idle keeps the folder it already has.
    private func refreshPlan() async {
        guard case .idle = sessions.state(for: task.id) else { return }
        await sessions.refreshPlan(taskID: task.id, branch: task.branch, taskNumber: task.taskNumber, noBranchNote: task.noBranchNote,
                                   worktreeLocation: worktreeLocation, baseRef: task.baseRef)
    }

    private static func startNote(_ agent: AgentKind) -> String {
        "Starting an agent runs \(AgentLaunch.displayName(agent)) in this task's folder under your account. It uses tokens and can change files; "
            + "it stops at the pipeline's approval gates and asks you here."
    }
}

/// The line under a tab's note naming the folder a start would use.
private enum TaskFolderText {
    static func planLine(_ plan: TaskFolderPlan) -> String {
        switch plan {
        case .existing(let folder, let branch):
            return "Opens in \(display(folder)), where \(branch) is checked out."
        case .existingOwn(let folder):
            return "Opens in \(display(folder)), the task's own worktree."
        case .create(let path, let branch):
            return "Creates a worktree for \(branch) at \(display(path))."
        case .createDetached(let path, let baseRef):
            return "Creates a detached worktree at \(display(path)) from \(shortRef(baseRef)). \(TaskFolderResolver.detachedNote)"
        case .root(_, let note):
            // The task-folder notes already end in a full stop.
            return "Opens at the project root: \(note.hasSuffix(".") ? String(note.dropLast()) : note)."
        }
    }

    private static func display(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// "refs/remotes/origin/main" reads as "origin/main".
    private static func shortRef(_ ref: String) -> String {
        for prefix in ["refs/remotes/", "refs/heads/"] where ref.hasPrefix(prefix) { return String(ref.dropFirst(prefix.count)) }
        return ref
    }
}

/// Above a running terminal: the folder's note, when it has one, and the button that ends the process.
private struct DockRunningBar: View {
    let note: String?
    let stopTitle: String
    let stop: () -> Void

    var body: some View {
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
                Button(stopTitle, action: stop)
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
