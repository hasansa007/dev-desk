import AppKit
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
    /// Returns whether the run was actually dispatched, so a caller recording a stage records only real starts.
    @discardableResult
    /// `command` is typed as given, for a line built elsewhere — a "Start with" command.
    func prepareRun(door: String, title: String, agent: String, arguments: [String] = [],
                    id: String? = nil, folderNote: String? = nil, mode: RunMode? = nil,
                    command prebuilt: String? = nil, taskNumber: Int? = nil) -> Bool {
        let runID = id ?? DoorRuns.id(door: door)
        // One run per door, and per task: a second start would give the same id two shells and the panel one row.
        guard canRunDoors, !isRunLive(runID),
              let command = prebuilt ?? DoorCommand.build(door: door, agent: agent, arguments: arguments,
                                                          home: NSHomeDirectory(),
                                                          mode: mode ?? RunModeChoice.current(for: ref))
        else {
            if isRunLive(runID) {
                selectedSessionID = runID
                go(.terminals)
            }
            runs.selectedID = isRunLive(runID) ? runID : runs.selectedID
            return false
        }
        // Only startAgent tracked this window's sessions, so a window whose runs are all door runs never
        // counted towards LiveShells' app-wide agentCount — and that count now decides whether a Start
        // queues (AgentSlots.free). Tracking is idempotent, so repeating it here costs nothing.
        LiveShells.shared.track(agentSessions: sessions)
        runs.add(DoorRun(id: runID, title: title, agent: agent, command: command,
                         folderNote: folderNote ?? (FreshBaseWorktree.doors.contains(door)
                            ? "a report door runs in a new worktree on origin's freshly fetched base branch."
                            : "a door reads the whole project, not one task's branch."),
                         // A local backlog entry has no number, so it takes a fresh base worktree like a report door.
                         freshBase: prebuilt == nil && (FreshBaseWorktree.doors.contains(door) || (door == "dev" && taskNumber == nil)),
                         taskNumber: prebuilt == nil ? taskNumber : nil))
        // Land on the run that was just started, the way starting an agent does. Without this the accordion
        // opened whatever was already live and the new row sat collapsed below it — a start with nothing to see.
        selectedSessionID = runID
        go(.terminals)
        Task { await sync() }
        return true
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
                          permission: .everything, directory: path, subject: draft.key,
                          mode: RunModeChoice.current(for: ref))
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
                          permission: .everything, directory: path, subject: task.id,
                          mode: RunModeChoice.current(for: ref))
    }

    /// Runs a connection's own sign-in or sign-out in a terminal. Dev Desk holds no credential and implements
    /// no OAuth: each CLI owns its keychain and its browser dance, and this is the one surface the app has for
    /// letting you watch it happen (decision 14). A scratch session, because auth belongs to no task.
    /// Signing in happens in the developer's own terminal (ADR 0036 §4.7), never in one Dev Desk hosts.
    /// Device-code flows, browser hand-offs and password prompts all want a real terminal, and decision 14
    /// is strongest when the app does not host the pty a credential travels through. Returns what happened,
    /// so the pane can say "copied" rather than nothing when Automation is refused.
    @discardableResult
    func runAuthCommand(_ command: String, connection: String) -> TerminalHandoff.Outcome {
        TerminalHandoff.run(command, in: projectRoot)
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
    func startTask(_ task: DeskTask, agent: String, using launch: TaskLaunch? = nil) {
        if task.isMerged { return }
        // A released card runs what was decided when it was parked, not what the preferences say now.
        let agent = launch.map { AgentLaunch.connectionName($0.agent) } ?? agent
        let mode = launch?.mode
        // "In queue if the limit is hit" (ADR 0035): with every agent slot busy, the Start parks the card
        // in Queued rather than running past the limit — StartQueueRunner releases it as slots free.
        if StartQueue.queuesInsteadOfStarting(task, freeSlots: AgentSlots.free) {
            if let parked = taskLaunch(for: task, agent: agent) { launchStore?.write(parked) }
            Task { await queueForStart(task) }
            return
        }
        // The launch is NOT cleared on dispatch: it is what this task was last started with, so the next
        // Start can run it without asking again and the sheet opens only the first time.
        if let entry = task.localBacklogID {
            // No issue to name. `/dev` takes a description as readily as a number, and the file is the description.
            if prepareRun(door: "dev", title: task.title, agent: agent,
                          arguments: ["\(task.title) — described in \(LocalBacklog.folder)/\(entry).md"],
                          id: DoorRuns.id(local: entry),
                          folderNote: "this has no issue yet; it runs in a fresh worktree on origin's base, where /dev cuts its branch.",
                          mode: mode) {
                // A start is the move to In progress (ADR 0035), recorded only when something was dispatched.
                Task { await recordStarted(task) }
            }
            return
        }
        guard let number = task.taskNumber else { return }
        if prepareRun(door: "dev", title: "Task #\(number)", agent: agent,
                      arguments: ["#\(number)"], id: DoorRuns.id(task: number),
                      folderNote: "#\(number) runs in its own worktree — its gh-\(number)- branch, or a fresh one on origin's base.",
                      mode: mode, taskNumber: number) {
            Task { await recordStarted(task) }
        }
    }

    /// The title and note `startTask` gives each kind of card, so a run row reads the same whoever carries it.
    private func runRow(for task: DeskTask, id: String) -> (title: String, note: String) {
        if task.localBacklogID != nil {
            return (task.title, "this has no issue yet; /dev cuts a branch at its first write.")
        }
        let number = task.taskNumber.map(String.init) ?? ""
        return ("Task #\(number)", "#\(number) has no branch yet; /dev cuts one at its first write.")
    }

    /// Starts a task with an entry from the developer's "Start with" list (ADR 0036 decision 6, widened).
    ///
    /// The launch is written first, to `.devdesk/start-with/` — never where a remembered launch is read, or the
    /// card's next Start would quietly run Claude here. An app is opened on the project folder with the prompt on
    /// the clipboard, because a folder is all nearly every app accepts. A command is typed into a Sessions
    /// terminal with its placeholders filled, so its output and any failure are where every other run is.
    func start(_ task: DeskTask, with entry: StartWithEntry, agent: String) {
        guard let root = projectRoot, let launch = taskLaunch(for: task, agent: agent),
              let prompt = launch.prompt(home: NSHomeDirectory()), let id = DoorRuns.id(for: task) else { return }
        let store = TaskLaunchStore(projectRoot: root, folder: TaskLaunchStore.startWithFolder)
        store.write(launch)
        switch entry.kind {
        case .app(let path):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            NSWorkspace.shared.open([root], withApplicationAt: URL(fileURLWithPath: path),
                                    configuration: NSWorkspace.OpenConfiguration())
            dismissSheet()
            Task { await recordStarted(task) }
        case .command(let template):
            let values = ["folder": root.path, "prompt": prompt, "taskFile": store.url(for: launch.id).path,
                          "title": task.title]
            let row = runRow(for: task, id: id)
            dismissSheet()
            if prepareRun(door: "dev", title: row.title, agent: entry.name, id: id, folderNote: row.note,
                          command: StartWithTemplate.render(template, values: values).line) {
                Task { await recordStarted(task) }
            }
        }
    }

    /// This project's launches, or nil for a project with no folder to keep them in.
    var launchStore: TaskLaunchStore? { projectRoot.map { TaskLaunchStore(projectRoot: $0) } }

    /// The launch this task was last started with, which is also what the queue reads. Its presence is what
    /// makes a start the task's second: the sheet opens once, and after that the same choice runs.
    func rememberedLaunch(for task: DeskTask) -> TaskLaunch? {
        DoorRuns.id(for: task).flatMap { launchStore?.read(id: $0) }
    }

    func remembersLaunch(for task: DeskTask) -> Bool { rememberedLaunch(for: task) != nil }

    /// Starts from the sheet's choice: the launch is remembered first, so the queue and the next Start both
    /// read what was decided here rather than a preference that may have moved since.
    func startTask(_ task: DeskTask, with launch: TaskLaunch) {
        launchStore?.write(launch)
        dismissSheet()
        startTask(task, agent: AgentLaunch.connectionName(launch.agent), using: launch)
    }

    /// Everything this Start decided, as one value (ADR 0036 decision 1): the door and its arguments, the
    /// agent and mode chosen now, where a worktree may go, and the base pinned to the commit it names.
    /// nil for a card `/dev` has nothing to open — the same cards `startBlockedReason` already refuses.
    func taskLaunch(for task: DeskTask, agent: String) -> TaskLaunch? {
        guard let kind = AgentLaunch.agent(forConnectionName: agent) else { return nil }
        guard let id = DoorRuns.id(for: task) else { return nil }
        // The same arguments `startTask` dispatches with: a local entry is described by its file, an issue by its number.
        let arguments = task.localBacklogID
            .map { ["\(task.title) — described in \(LocalBacklog.folder)/\($0).md"] }
            ?? task.taskNumber.map { ["#\($0)"] } ?? []
        return TaskLaunch(id: id, task: task.id, title: task.title, door: "dev", arguments: arguments,
                          agent: kind, mode: RunModeChoice.current(for: ref),
                          worktreeLocation: UserDefaults.standard.string(forKey: PreferenceKey.worktreeLocation)
                              ?? AgentDefaults.worktreeLocation,
                          base: task.baseRef.map { LaunchBase(ref: $0, short: task.baseShort) })
    }

    /// Why this task cannot be started, or nil when it can.
    func startBlockedReason(for task: DeskTask, agent: String) -> String? {
        if task.isMerged { return "This work is merged; open the pull request to see it." }
        if task.isLocalBacklog { return runBlockedReason(agent: agent) }
        guard task.taskNumber != nil else { return "This card has no issue number, so `/dev` has nothing to open." }
        if let blocker = openBlocker(of: task) {
            return "Waits for #\(blocker), which is still open. Finish it first, or remove the needs:/blocked by line from this issue."
        }
        return runBlockedReason(agent: agent)
    }

    /// The first issue this card records it waits on that is still on the board and not done (ADR 0046).
    func openBlocker(of task: DeskTask) -> Int? {
        task.dependencies.filter { $0.text.hasPrefix("Blocked by") }.compactMap { $0.taskID.flatMap { Int($0) } }
            .first { number in tasks.contains { $0.issueNumber == number && $0.column != .done } }
    }

    /// Why the button that would start `agent` is disabled, or nil when it can run.
    func runBlockedReason(agent: String) -> String? {
        if !canRunDoors { return "Sample projects have no folder, so there is nothing to run in." }
        if DoorCommand.agent(named: agent) == nil {
            return "\(agent) has no invocation this family has verified. Choose another agent in Settings."
        }
        return nil
    }
}
