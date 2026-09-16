import DeskCore
import SwiftUI

/// A shell in the folder a task or a run resolves to. Nothing runs until Start, and the shell belongs to the
/// window's registry, so it outlives this pane.
struct ShellPane: View {
    let sessions: ShellSessions
    /// The session key: a task's id, or a run's.
    let id: String
    var branch: String?
    var taskNumber: Int?
    var folderNote: String?
    /// Typed into the shell once it is running, as the user would type it; nil leaves a plain prompt.
    var command: String?
    var startTitle = "Start shell"
    /// Terminals puts Stop in the row's own header, where a collapsed row can still reach it, so the pane does
    /// not add a second button for the same action.
    var showsStop = true
    /// Terminals puts Start in the row's header too, so the pane shows the note without repeating the button.
    var showsStart = true

    @Environment(\.terminals) private var terminals
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation

    static let trustNote = "Starting a shell runs your login shell and git in this repository, as Terminal would. Only start one in a repository you trust."

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeskColor.terminalGround)
            .task(id: id) { await refreshPlan() }
    }

    @ViewBuilder private var content: some View {
        switch sessions.state(for: id) {
        case .idle(let plan):
            DockMessage(text: Self.trustNote, detail: detail(plan)) {
                if showsStart {
                    Button(startTitle) { start() }
                        .disabled(terminals == nil)
                }
            }
        case .preparing:
            DockMessage(text: "Preparing the folder…")
        case .running(let folder):
            VStack(spacing: 0) {
                if showsStop {
                    TaskRunningBar(note: folder.note, usage: usage, stopTitle: "End shell") { terminals?.end(taskID: id) }
                } else {
                    // The note is a one-line header over the terminal, so it must take only its own height. It
                    // used to be a DockMessage, whose body is a ScrollView — and a ScrollView claims all the
                    // vertical space it is offered, so it grew to fill the pane and squeezed the terminal into a
                    // short strip at the bottom. That strip, drawn top-anchored, put the prompt partway down with
                    // a band of empty ground above and below it. TaskRunningBar is a fixed-height row, so the
                    // terminal below now gets the rest of the pane.
                    if let note = folder.note {
                        TaskRunningBar(note: note, usage: nil)
                    }
                    // Terminals keeps Stop in the row's own header, so the bar here carries the meter alone —
                    // and appears only when there is a reading, since an agent that has said nothing yet has
                    // nothing to show.
                    if usage != nil { TaskRunningBar(note: nil, usage: usage) }
                }
                if let terminals {
                    ShellTerminalView(terminals: terminals, taskID: id)
                }
            }
            .task(id: id) { await trackUsage() }
        case .ended(_, let status):
            // With the last lines the process wrote, kept by the registry as it exited: a pane that says only
            // "Shell ended" hides the one line that explains a run which died at launch, and a failed diagram
            // generate's session is kept open exactly so these words stay readable.
            let tail = sessions.outputTail(for: id)
            DockMessage(text: status.map { "Shell ended (status \($0))." } ?? "Shell ended.",
                        detail: tail.isEmpty ? nil : tail.suffix(12).joined(separator: "\n")) {
                if showsStart {
                    Button("Start again") { start() }
                        .disabled(terminals == nil)
                }
            }
        case .failed(let message):
            DockMessage(text: message)
        }
    }

    /// Where the shell will open, and what it will be told to run, both before anything starts.
    private func detail(_ plan: TaskFolderPlan?) -> String? {
        let lines = [plan.map(TaskFolderText.planLine), command.map { "Runs: \($0)" }].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The values are taken at the click, so the shell starts once the folder is ready even if the user has moved on by then.
    private func start() {
        guard let terminals else { return }
        let id = self.id
        let branch = self.branch
        let taskNumber = self.taskNumber
        let note = self.folderNote
        let command = self.command
        let location = worktreeLocation
        Task {
            await sessions.start(taskID: id, branch: branch, taskNumber: taskNumber, noBranchNote: note, worktreeLocation: location)
            guard case .running(let folder) = sessions.state(for: id) else { return }
            terminals.start(taskID: id, folder: folder.url)
            guard let command else { return }
            // A login shell reads nothing until it has drawn its first prompt; typed sooner, the line is swallowed.
            try? await Task.sleep(for: .milliseconds(700))
            terminals.sendCommand(command, to: id)
        }
    }

    /// The newest reading for this session, taken from the agent's own log; nil until there is one.
    private var usage: ContextUsage? { sessions.usage(for: id) }

    /// Which CLI this session is running, from the executable the registry launched into it. A login shell is
    /// not an agent and has none, and a Debug build's stand-in executable is not one either — both mean no
    /// meter, which is right: neither writes the session log the meter is read from.
    private var agent: AgentKind? {
        terminals.flatMap { AgentKind(rawValue: $0.executables[id] ?? "") }
    }

    /// An interactive agent writes its JSON to its own session log rather than to the app, so the meter is
    /// polled from that file while the session runs. Leaving the pane cancels this task, and the polling with it.
    private func trackUsage() async {
        guard let agent else { return }
        await sessions.trackUsage(taskID: id, agent: agent)
    }

    /// Asking git for its worktrees is read-only; a session past idle keeps the folder it already has.
    private func refreshPlan() async {
        guard case .idle = sessions.state(for: id) else { return }
        await sessions.refreshPlan(taskID: id, branch: branch, taskNumber: taskNumber,
                                   noBranchNote: folderNote, worktreeLocation: worktreeLocation)
    }

}

/// The line under a pane's note naming the folder a start would use.
enum TaskFolderText {
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

/// Above a running terminal: the folder's note, when it has one, how much context the agent is holding, when
/// it has reported any, and the button that ends the process.
struct TaskRunningBar: View {
    let note: String?
    /// The agent's own reading, read from its session log. Nil shows nothing: an agent that has reported
    /// nothing, and a plain shell that never will, both leave the bar as it was.
    var usage: ContextUsage?
    /// Terminals keeps Stop in the row's own header, so the bar is also built without a button — then it is
    /// only what the session is saying about itself.
    var stopTitle: String?
    var stop: (() -> Void)?

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
                if let usage {
                    Text(usage.label)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.terminalDim2)
                        .lineLimit(1)
                        .help("How much of its context this agent is holding, as its own CLI reports it")
                }
                Spacer(minLength: 0)
                if let stopTitle, let stop {
                    Button(stopTitle, action: stop)
                        .buttonStyle(TaskDockControlStyle())
                        .fixedSize()
                }
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
struct DockMessage<Actions: View>: View {
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

struct TaskDockControlStyle: ButtonStyle {
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
