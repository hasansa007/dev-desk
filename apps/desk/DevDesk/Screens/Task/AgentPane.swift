import DeskCore
import SwiftUI

/// The task's agent: Claude Code or Codex, in the task's own folder. Nothing runs until Start agent is clicked
/// or Auto starts it, and the agent belongs to the window's registry, so it outlives this pane.
struct AgentPane: View {
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
                TaskRunningBar(note: folder.note, stopTitle: "Stop agent") { agents?.end(taskID: task.id) }
                if let agents {
                    ShellTerminalView(terminals: agents, taskID: task.id)
                }
            }
        case .ended(let folder, let status):
            startable(Self.endedLine(status, executable: agents?.executables[task.id]), detail: { _ in folder.note }, button: "Start again")
        case .failed(let message):
            // Auto won't run an agent at the project root, so its start fails here with the folder's note. Starting by hand may run it
            // there, so what starting does comes with it.
            if model.ref.isSample {
                DockMessage(text: message)
            } else {
                startable(message, detail: Self.startNote, button: "Start agent")
            }
        }
    }

    /// The message with the start button, or with the reason the agent can't start.
    @ViewBuilder private func startable(_ text: String, detail: (AgentKind) -> String?, button: String) -> some View {
        switch choice {
        case .ready(let agent):
            DockMessage(text: text, detail: detail(agent)) {
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

    /// Status 127 is a shell's "command not found", so that line says where the PATH is set.
    private static func endedLine(_ status: Int32?, executable: String?) -> String {
        guard let status else { return "Agent ended." }
        guard status == 127, let executable else { return "Agent ended (status \(status))." }
        return "Agent ended (status 127): your login shell couldn't find \(executable). Put it on your PATH in ~/.zprofile or ~/.zshrc."
    }
}
