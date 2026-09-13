import DeskCore
import SwiftUI

/// What starting a door and a task involves, and how a session's state reads. These outlived the Runs panel
/// they were written in: the panel was a second list of the sessions Terminals already shows, with the same
/// Open and Stop, so it went (ADR 0026's glance is the sidebar's own live count).
enum RunLabel {
static func label(for state: ShellSessionState) -> (label: String, tone: StatusTone, pulses: Bool, isLive: Bool) {
    switch state {
    case .idle: return ("Not started", .neutral, false, false)
    case .preparing: return ("Preparing the folder", .info, true, true)
    case .running: return ("Running", .running, true, true)
    case .ended(_, let status): return (status.map { "Ended (status \($0))" } ?? "Ended", .ended, false, false)
    case .failed(let reason): return (reason, .failed, false, false)
    }
}
}

extension ProjectWindowModel {
    /// A sample project has no folder on disk, so no door can run in it.
    var canRunDoors: Bool {
        if case .local = ref { return true }
        return false
    }

    /// Lists the door as a run and opens the panel. Nothing executes until the pane's own Start, per ADR 0017.
    /// `id` separates runs of the same door for different tasks; the folder rule prefixes `folderNote` with where it opens.
    func prepareRun(door: String, title: String, agent: String, arguments: [String] = [],
                    id: String? = nil, folderNote: String? = nil) {
        let runID = id ?? DoorRuns.id(door: door)
        // One run per door, and per task: a second start would give the same id two shells and the panel one row.
        guard canRunDoors, !isRunLive(runID),
              let command = DoorCommand.build(door: door, agent: agent, arguments: arguments, home: NSHomeDirectory())
        else {
            if isRunLive(runID) { go(.terminals) }
            runs.selectedID = isRunLive(runID) ? runID : runs.selectedID
            return
        }
        runs.add(DoorRun(id: runID, title: title, agent: agent, command: command,
                         folderNote: folderNote ?? "a door reads the whole project, not one task's branch."))
        go(.terminals)
    }

    /// Approving an item files it through `dev:create-issue` rather than writing the issue here, so the door's
    /// checks and this repository's labels still apply to anything that reaches the backlog.
    /// Filing is not somewhere you go. It drafts an issue with this repository's own labels and files it, which
    /// takes a door and a minute — so it runs in the BACKGROUND and you stay on the report you are reading.
    /// It used to open a terminal and jump you to it, which answered a question nobody asked.
    ///
    /// Returns the job so the caller can show it filing, or nil when the door cannot run here.
    @discardableResult
    func fileFromReport(jobs: JobRegistry?, itemID: String, description: String, agent: String) -> String? {
        guard let jobs, case .local(let path) = ref else {
            // No background registry (a sample project, or a preview): fall back to the terminal it used to use.
            prepareRun(door: "create-issue", title: "File \(itemID)", agent: agent, arguments: [description],
                       id: DoorRuns.id(door: "create-issue:\(itemID)"),
                       folderNote: "filing reads the tracker, so it runs at the project root.")
            return nil
        }
        return jobs.start(door: "create-issue", title: "File \(itemID)", agent: agent, arguments: [description],
                          permission: .everything, directory: path)
    }

    /// Starts `/dev #N` for a task. The card and the dialog both call this, so they cannot disagree about
    /// what starting means, and the one-run-per-task rule in `prepareRun` still holds across both.
    func startTask(_ task: DeskTask, agent: String) {
        guard let number = task.taskNumber else { return }
        prepareRun(door: "dev", title: "Task #\(number)", agent: agent,
                   arguments: ["#\(number)"], id: DoorRuns.id(task: number),
                   folderNote: "#\(number) has no branch yet; /dev cuts one at its first write.")
    }

    /// Why this task cannot be started, or nil when it can.
    func startBlockedReason(for task: DeskTask, agent: String) -> String? {
        guard task.taskNumber != nil else { return "This card has no issue number, so `/dev` has nothing to open." }
        return runBlockedReason(agent: agent)
    }

    /// Why the button that would start `agent` is disabled, or nil when it can run.
    func runBlockedReason(agent: String) -> String? {
        if !canRunDoors { return "Sample projects have no folder, so there is nothing to run in." }
        if DoorCommand.agent(named: agent) == nil {
            return "\(agent) has no invocation this family has verified. Choose Claude or Codex in Settings."
        }
        return nil
    }
}
