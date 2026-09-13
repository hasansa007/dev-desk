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
            if isRunLive(runID) {
                selectedSessionID = runID
                go(.terminals)
            }
            runs.selectedID = isRunLive(runID) ? runID : runs.selectedID
            return
        }
        runs.add(DoorRun(id: runID, title: title, agent: agent, command: command,
                         folderNote: folderNote ?? "a door reads the whole project, not one task's branch."))
        // Land on the run that was just started, the way starting an agent does. Without this the accordion
        // opened whatever was already live and the new row sat collapsed below it — a start with nothing to see.
        selectedSessionID = runID
        go(.terminals)
    }

    // MARK: - Filing (ADR 0027)

    /// Why filing goes to `docs/backlog/` rather than a tracker, or nil when there is a tracker to file into.
    /// `dev:create-issue` writes to GitHub; when gh cannot see the repository, a run told to file anyway does
    /// not stop — it retries in the background. So the work is recorded locally instead, and promoted later.
    var localBacklogReason: String? {
        guard let github = snapshot?.connections.first(where: { $0.id == "github" }),
              github.state == .unavailable else { return nil }
        return "GitHub is unavailable here (\(github.label))"
    }

    /// Where a press of "Add to backlog" will put this, in the words a button's help can use.
    var backlogDestination: String {
        localBacklogReason.map { "Writes it to docs/backlog/ — \($0). It can be filed on GitHub later." }
            ?? "Queues dev:create-issue for it; it drafts and files with this repository's labels"
    }

    /// Why this item cannot be filed right now, or nil when it can. One answer for the card, the dialog and
    /// Ideation, so no two of them disagree about whether the same item can be filed.
    func fileBlockedReason(key: String, job: BackgroundJob?, agent: String) -> String? {
        if isInLocalBacklog(key) { return "Already in docs/backlog/." }
        if let job, job.state.isLive { return "A run is already filing this one." }
        if let job, case .asking = job.state { return "The run filing this one is waiting for an answer." }
        if let job, case .ended(_, let failed) = job.state, !failed { return "This one has been filed." }
        // Writing a file needs no agent — only a folder to write it in.
        if localBacklogReason != nil, snapshot?.repositoryRoot != nil { return nil }
        return runBlockedReason(agent: agent)
    }

    /// Files one item into whichever backlog this project has: `docs/backlog/` at once when there is no tracker,
    /// otherwise `dev:create-issue` in the background, so you stay on what you were reading.
    ///
    /// Returns the job id when a run was started, so the caller can show it filing.
    @discardableResult
    func fileToBacklog(_ draft: BacklogDraft, jobs: JobRegistry?, agent: String) -> String? {
        if localBacklogReason != nil {
            Task { await fileLocally(draft) }
            return nil
        }
        guard let jobs, case .local(let path) = ref else {
            // No background registry (a sample project, or a preview): fall back to the terminal it used to use.
            prepareRun(door: "create-issue", title: "File \(draft.key)", agent: agent, arguments: [draft.description],
                       id: DoorRuns.id(door: "create-issue:\(draft.key)"),
                       folderNote: "filing reads the tracker, so it runs at the project root.")
            return nil
        }
        // One run per item, wherever the call came from. Two runs drafting the same finding file two issues
        // for it, and the second is discovered by reading the tracker afterwards.
        if let existing = jobs.job(subject: draft.key, in: path) {
            switch existing.state {
            case .starting, .running, .asking: return existing.id
            case .ended(_, let failed): if !failed { return existing.id }
            }
        }
        return jobs.start(door: "create-issue", title: "File \(draft.key)", agent: agent, arguments: [draft.description],
                          permission: .everything, directory: path, subject: draft.key)
    }

    /// Promotes a local entry to a GitHub issue — only ever on request, never because a remote appeared. The
    /// door reads the file itself, so the issue carries the whole entry rather than a one-line summary of it.
    /// When the run reports its number, `FiledWorkHook` moves the file to `filed/`.
    @discardableResult
    func promoteLocalItem(_ task: DeskTask, jobs: JobRegistry?, agent: String) -> String? {
        guard localBacklogReason == nil, let jobs, case .local(let path) = ref,
              let item = localBacklogItem(for: task), item.issue == nil else { return nil }
        if let existing = jobs.job(subject: task.id, in: path), existing.state.isLive { return existing.id }
        let file = "\(LocalBacklog.folder)/\(item.id).md"
        return jobs.start(door: "create-issue", title: "File \(item.title)", agent: agent,
                          arguments: ["\(item.title). The full description is in \(file); file it as written, and report the issue URL."],
                          permission: .everything, directory: path, subject: task.id)
    }

    /// Runs a connection's own sign-in or sign-out in a terminal. Dev Desk holds no credential and implements
    /// no OAuth: each CLI owns its keychain and its browser dance, and this is the one surface the app has for
    /// letting you watch it happen (decision 14). A scratch session, because auth belongs to no task.
    func runAuthCommand(_ command: String, connection: String) {
        guard canRunDoors else { return }
        let id = "auth:\(connection.lowercased())"
        guard !isRunLive(id) else {
            selectedSessionID = id
            go(.terminals)
            return
        }
        runs.add(DoorRun(id: id, title: "\(connection) · \(command)", agent: connection, command: command,
                         folderNote: "signing in is the tool's own command, so it runs at the project root."))
        selectedSessionID = id
        go(.terminals)
    }

    /// Runs the CLI's own check in a terminal at the project root: `dev doctor` already reports what is
    /// installed, linked and reachable, so the app asks it rather than growing a second opinion of its own.
    func runDoctor() {
        guard canRunDoors else { return }
        let id = DoorRuns.id(door: "doctor")
        guard !isRunLive(id) else {
            selectedSessionID = id
            go(.terminals)
            return
        }
        runs.add(DoorRun(id: id, title: "dev doctor", agent: "dev", command: "dev doctor",
                         folderNote: "doctor checks this machine and this repository, so it runs at the project root."))
        selectedSessionID = id
        go(.terminals)
    }

    // MARK: - Starting

    /// Starts `/dev` for a task. The card and the dialog both call this, so they cannot disagree about what
    /// starting means, and the one-run-per-task rule in `prepareRun` still holds across both.
    func startTask(_ task: DeskTask, agent: String) {
        if let entry = task.localBacklogID {
            // No issue to name. `/dev` takes a description as readily as a number, and the file is the description.
            prepareRun(door: "dev", title: task.title, agent: agent,
                       arguments: ["\(task.title) — described in \(LocalBacklog.folder)/\(entry).md"],
                       id: DoorRuns.id(local: entry),
                       folderNote: "this has no issue yet; /dev cuts a branch at its first write.")
            return
        }
        guard let number = task.taskNumber else { return }
        prepareRun(door: "dev", title: "Task #\(number)", agent: agent,
                   arguments: ["#\(number)"], id: DoorRuns.id(task: number),
                   folderNote: "#\(number) has no branch yet; /dev cuts one at its first write.")
    }

    /// Why this task cannot be started, or nil when it can.
    func startBlockedReason(for task: DeskTask, agent: String) -> String? {
        if task.isLocalBacklog { return runBlockedReason(agent: agent) }
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
