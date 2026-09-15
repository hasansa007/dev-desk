import DeskCore
import SwiftUI

/// Generating one `dev:arch` diagram from the Diagrams screen, in the background. The screen never leaves
/// itself: the run is a scratch session that appears in Sessions and runs the headless `dev:arch` argv, so its
/// process exits when the diagram is written. `ShellSessions.onSessionEnded` (wired in the model) then clears
/// the kind's spinner, reloads so the new HTML is picked up, and takes the finished session off the list.
extension ProjectWindowModel {
    /// Why a diagram cannot be generated right now, or nil when it can. A sample has no folder; an agent with
    /// no verified invocation cannot run; and one run per kind at a time, so a second press does nothing.
    func diagramGenerateBlockedReason(kind: String, agent: String) -> String? {
        if isGeneratingDiagram(kind: kind) { return "This diagram is being generated." }
        return runBlockedReason(agent: agent)
    }

    /// Starts the headless `dev:arch` for one kind, in the background, without changing tab. `target` scopes it
    /// to a subsystem (empty draws the whole project). Nothing happens when it is blocked, so the caller can
    /// wire it straight to a button under `diagramGenerateBlockedReason`.
    func generateDiagram(kind: String, target: String, agent: String, terminals: ShellTerminalRegistry,
                         worktreeLocation: String) {
        guard diagramGenerateBlockedReason(kind: kind, agent: agent) == nil,
              let launch = ArchRun.launch(agent: agent, kind: kind, target: target, home: NSHomeDirectory())
        else { return }
        // A scratch terminal, so it lands in Sessions like any other session — but selecting it is not the same
        // as showing it: the Diagrams screen stays in front, and only the kind's own pane shows the spinner.
        let previous = selectedSessionID
        let id = newTerminal()
        selectedSessionID = previous
        beginGeneratingDiagram(kind: kind, sessionID: id)
        Task {
            await sessions.start(taskID: id, branch: nil, taskNumber: nil, noBranchNote: nil,
                                 worktreeLocation: worktreeLocation, title: "Diagram · \(kind)")
            guard case .running(let folder) = sessions.state(for: id) else {
                // The folder never materialised, so nothing will run and nothing will end: clear the spinner now.
                finishGeneratingDiagram(sessionID: id)
                closeTerminal(id)
                return
            }
            terminals.start(taskID: id, folder: folder.url, command: launch)
        }
    }
}
