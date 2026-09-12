import DeskCore
import SwiftUI

/// A run's terminal at dialog size. The Runs panel is a strip along the bottom edge; a run that stops to ask
/// "1. Accept · 5. Chat about this" cannot be answered in a strip, and the answer is the point of the run.
///
/// One host at a time: while this is open the panel shows its list only, because an NSView cannot live in two
/// view hierarchies at once.
struct RunDialog: View {
    let model: ProjectWindowModel
    let id: String
    @Environment(\.shellTerminals) private var terminals
    @Environment(\.agentTerminals) private var agents

    private var run: DoorRun? { model.runs.run(id) }
    private var task: DeskTask? { model.tasks.first { $0.id == id } }

    /// A row is either a door this window started or a task's own agent, and each lives in its own registry.
    private var isAgent: Bool { run == nil && model.agentSessions.state(for: id).isLive }

    var body: some View {
        SheetChrome(title: title, confirmTitle: "Stop", confirmDisabled: !isLive,
                    cancelTitle: "Close",
                    onCancel: model.dismissSheet, onConfirm: stop) {
            VStack(alignment: .leading, spacing: 8) {
                Text(caption)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private var pane: some View {
        if let run {
            ShellPane(sessions: model.shellSessions, id: run.id, folderNote: run.folderNote,
                      command: run.command, startTitle: "Start run")
        } else if let task {
            // The agent and the terminal are the same machinery with different argv, and each has its own pane
            // and its own registry; the dialog picks the one whose session this id belongs to.
            if isAgent {
                AgentPane(model: model, task: task)
            } else {
                ShellPane(sessions: model.shellSessions, id: task.id, branch: task.branch,
                          taskNumber: task.taskNumber, startTitle: "Start shell")
            }
        } else {
            UnavailableView(reason: "This run is no longer on the board.")
        }
    }

    private var isLive: Bool {
        model.shellSessions.state(for: id).isLive || model.agentSessions.state(for: id).isLive
    }

    private var title: String { run?.title ?? task?.title ?? "Run" }

    private var caption: String {
        if run != nil { return "A door reads the whole project, not one task's branch." }
        return isAgent ? "The agent types. It stops at each gate and asks you here."
                       : "You type the commands, in this task's folder."
    }

    private func stop() {
        model.dismissSheet()
        agents?.end(taskID: id)
        terminals?.end(taskID: id)
    }
}
