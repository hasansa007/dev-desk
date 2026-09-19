import DeskCore
import SwiftUI

/// Generating one `dev:arch` diagram from the Diagrams screen. The run is an interactive session in Sessions,
/// opened in front so it is watched and answered like any other door. The Diagrams screen re-reads the folder
/// while the kind is generating and swaps its spinner for the drawing once a newer file lands; the session stays
/// open until the developer ends it.
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
    /// `kind` is what the run is tracked under — a kind, or a flow's key — and `drawKind` the type drawn when they
    /// differ: a flow's sequence is tracked by its flow and drawn as `sequence`, into `outputName` (ADR 0047).
    func generateDiagram(kind: String, drawKind: String? = nil, outputName: String? = nil, target: String,
                         agent: String, terminals: ShellTerminalRegistry, worktreeLocation: String) {
        guard diagramGenerateBlockedReason(kind: kind, agent: agent) == nil,
              let launch = ArchRun.launch(agent: agent, kind: drawKind ?? kind, target: target,
                                          home: NSHomeDirectory(), outputName: outputName)
        else { return }
        // A terminal in Sessions, shown: a run nobody can see is one whose questions nobody answers.
        let id = newTerminal()
        selectedSessionID = id
        go(.terminals)
        beginGeneratingDiagram(kind: kind, sessionID: id)
        Task {
            await sessions.start(taskID: id, branch: nil, taskNumber: nil, noBranchNote: nil,
                                 worktreeLocation: worktreeLocation, title: "Diagram · \(target.isEmpty ? kind : target)")
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
