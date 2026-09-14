import DeskCore
import SwiftUI

/// Every session this window is running, side by side. The **only** host of a live terminal (ADR 0026): a
/// terminal is an NSView and can live in exactly one view hierarchy, so a second surface showing the same one
/// draws an empty frame while the first keeps it.
///
/// One, two or four up, because parallel work is the app's own premise — Auto runs up to three agents — and
/// that is the thing an edge panel and a modal both cannot do.
struct TerminalsScreen: View {
    @Bindable var model: ProjectWindowModel
    @State private var expandedID: String?
    @State private var hasChosen = false
    /// What was live when the app was last killed (ADR 0031). Records, not sessions: nothing here is running.
    @State private var recovered: [JournalRecord] = []
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var rows: [SessionRow] { SessionRow.all(in: model, jobs: jobs) }
    /// Nil for a sample, which has no folder to have written anything in.
    private var journal: RunJournal? { model.sessions.journal }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty, recovered.isEmpty {
                EmptyStateView(title: "Nothing running",
                               message: "Start a task from the board, or run a door from Survey, Ideation or Roadmap. Whether it takes a terminal or runs in the background, it appears here.") {
                    Button("Go to the board") { model.go(.board) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary))
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        .onAppear(perform: syncExpansion)
        .onAppear(perform: loadRecovered)
        .onChange(of: model.selectedSessionID) { _, id in
            guard let id else { return }
            hasChosen = true
            expandedID = id
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Terminals")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Text(rows.isEmpty ? "nothing running" : "\(rows.count) running")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 0)
            Button("New terminal") {
                hasChosen = true
                expandedID = model.newTerminal()
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            .disabled(model.sessions.startRefusal(for: .shell) != nil)
            .help(model.sessions.startRefusal(for: .shell) ?? "A login shell at the project root")
        }
        .screenHeaderBar()
    }

    /// An accordion, not a grid. Two terminals at half height are two terminals you cannot read, and only the
    /// expanded one hosts its view — which is the one-host rule (ADR 0026) enforced by the layout rather than
    /// remembered by whoever adds the next surface.
    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !recovered.isEmpty { recoveredSection }
                ForEach(rows) { row in
                    TerminalTile(model: model, row: row, isExpanded: expandedID == row.id) {
                        hasChosen = true
                        expandedID = expandedID == row.id ? nil : row.id
                    }
                }
            }
            .padding(12)
        }
    }

    /// Which row is open. Arriving from a card or a door start lands on that session; after that it is whatever
    /// you last clicked, including nothing.
    ///
    /// It has to be real state. Deriving it as `selection ?? firstLive` meant collapsing a row set the selection
    /// to nil and the fallback immediately re-opened the same row — the chevron did nothing, every time.
    private func syncExpansion() {
        guard !hasChosen else { return }
        expandedID = model.selectedSessionID ?? rows.first(where: \.isLive)?.id ?? rows.first?.id
    }

    /// Above the live rows, because it is what happened while the app was gone and the live ones are now.
    private var recoveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovered")
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                Text("These were running when Dev Desk last closed unexpectedly. Nothing was restarted — continuing one is your call.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(recovered) { record in
                RecoveredTile(record: record, resume: resumeAction(for: record), handoff: handoff(for: record)) {
                    dismiss(record)
                }
            }
        }
    }

    /// Reading the journal is the whole of the launch behaviour: nothing is restarted, and ADR 0025 stands. A
    /// record whose run is live in this app is not a recovery — it is the row right below.
    private func loadRecovered() {
        guard let journal, recovered.isEmpty else { return }
        recovered = journal.recover().filter {
            jobs?.job($0.id) == nil && !model.sessions.runningTaskIDs.contains($0.id)
        }
        // The offer has now been made, so the graceful history goes. The unclean records stay until the user
        // acts on them: dismissing one for them is answering for them.
        journal.purgeClean()
    }

    /// Offered only where it is real: a background run that reported a session id before the app died. Anything
    /// else gets a handoff, which says what it actually does.
    private func resumeAction(for record: JournalRecord) -> (() -> Void)? {
        guard record.kind == .backgroundRun, record.sessionID != nil, let jobs else { return nil }
        return {
            guard jobs.resumeFromRecord(record) != nil else { return }
            recovered.removeAll { $0.id == record.id }
        }
    }

    /// The honest second best. It never claims the old conversation is back: a session is re-opened for the
    /// task, or the door is run again from its start.
    private func handoff(for record: JournalRecord) -> RecoveredTile.Handoff? {
        switch record.kind {
        case .terminalSession:
            guard model.task(record.id) != nil else { return nil }
            return RecoveredTile.Handoff(title: "Open the task",
                                         help: "Opens the task so you can start a session again. It starts fresh — the agent's own conversation is not restored.") {
                model.openTask(record.id)
            }
        case .backgroundRun:
            guard record.sessionID == nil, let door = record.door, !door.isEmpty, let jobs else { return nil }
            return RecoveredTile.Handoff(title: "Run the door again",
                                         help: "Starts a new \(door) run from the beginning. The interrupted one reported no session, so there is nothing to continue.") {
                jobs.start(door: door, title: record.title, agent: record.agent,
                           permission: record.permission.flatMap(RunPermission.init(rawValue:)) ?? .readOnly,
                           directory: record.directory, subject: record.subject,
                           mode: record.mode.flatMap(RunMode.init(rawValue:)) ?? .standard)
                dismiss(record)
            }
        }
    }

    private func dismiss(_ record: JournalRecord) {
        journal?.clear(id: record.id)
        recovered.removeAll { $0.id == record.id }
    }
}

/// A run the app died under: what it was, how far it got, and what can honestly be done about it now. It looks
/// like a session row and behaves like none — there is no terminal to host, because the process is long gone
/// (ADR 0025). Every button here is the user's own decision (ADR 0031).
private struct RecoveredTile: View {
    struct Handoff {
        let title: String
        let help: String
        let action: () -> Void
    }

    let record: JournalRecord
    let resume: (() -> Void)?
    let handoff: Handoff?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(tone: .ended, pulses: false)
                Text(record.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                // Relative and ticking: "two days ago" is the difference between a run worth continuing and one
                // whose repository has moved on without it.
                Text(record.lastSeenAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let resume {
                    Button("Resume", action: resume)
                        .buttonStyle(DeskButtonStyle(kind: .primary, size: .mini))
                        .help("Continues the same agent session this run reported before it was lost.")
                }
                if let handoff {
                    Button(handoff.title, action: handoff.action)
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help(handoff.help)
                }
                Button("Dismiss", action: dismiss)
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Forgets this record. Nothing else changes.")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(DeskColor.headerFill)
            if !record.logTail.isEmpty {
                Rectangle().fill(DeskColor.divider).frame(height: 1)
                log
            }
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    /// What it was, and the last state the app saw it in — the two things a row answers before any button.
    private var subtitle: String {
        let what: String
        switch record.kind {
        case .backgroundRun: what = [record.agent, record.door].compactMap { $0 }.joined(separator: " · ")
        case .terminalSession: what = record.purpose == "agent" ? "Agent" : "Terminal"
        }
        return "\(what) · \(record.stateLabel)"
    }

    /// The end of what it wrote, not all of it: this is a row, and the run it belonged to cannot add to it.
    private var log: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(record.logTail.suffix(6).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
    }
}

/// One session in the grid: what it is, what it is doing, and its terminal.
private struct TerminalTile: View {
    let model: ProjectWindowModel
    let row: SessionRow
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.terminals) private var terminals
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The expander is its own button and Stop is its sibling. A tap gesture on the whole row
                // swallows the clicks of the buttons inside it — the same way the card's outer Button ate its
                // own Start, and reported the same way: "stop is not working".
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(DeskColor.mutedInk)
                            .frame(width: 12)
                        StatusDot(tone: row.isLive ? .running : .ended, pulses: row.isLive)
                        Text(row.title)
                            .font(DeskFont.body.weight(.semibold))
                            .foregroundStyle(DeskColor.ink)
                            .lineLimit(1)
                        Text(row.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(DeskColor.mutedInk)
                            .lineLimit(1)
                        // A background run has no clock of its own. This one ticks by itself, so a run that
                        // has been "running" for twenty minutes reads as one.
                        if case .job(let job) = row.kind, job.state.isLive {
                            Text(job.startedAt, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(DeskColor.faintInk)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(row.title)")
                // The row's action, where a row's action belongs: top right, and primary when it is the thing
                // to do. It was a small button buried under the trust note in the body.
                if case .job(let job) = row.kind {
                    if job.state.isLive {
                        Button("Stop") { jobs?.stop(job.id) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    } else {
                        Button("Remove") { jobs?.remove(job.id) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                            .help("Takes the finished run off this list")
                    }
                } else if row.isLive {
                    Button("Stop") { terminals?.end(taskID: row.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                } else {
                    if case .scratch = row.kind {
                        Button("Close") { model.closeTerminal(row.id) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                            .help("Remove this terminal from the list")
                    }
                    Button(startTitle) { start() }
                        .buttonStyle(DeskButtonStyle(kind: .primary, size: .mini))
                        .disabled(terminals == nil)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(DeskColor.headerFill)
            if isExpanded {
                Rectangle().fill(DeskColor.divider).frame(height: 1)
                pane
                    .frame(maxWidth: .infinity, minHeight: DeskMetric.terminalTileTallHeight,
                           maxHeight: DeskMetric.terminalTileTallHeight)
            }
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    private var startTitle: String {
        if case .ended = model.sessions.state(for: row.id) { return "Start again" }
        switch row.kind {
        case .door: return "Start run"
        case .task: return "Start"
        case .scratch: return "Start terminal"
        // A background run has no shell to start; its row offers Stop or Remove instead.
        case .job: return "Start"
        }
    }

    /// The same start the pane does, from the header — the pane's own button is suppressed so one row asks once.
    private func start() {
        guard let terminals else { return }
        let id = row.id
        let branch: String?
        let number: Int?
        let note: String?
        let command: String?
        switch row.kind {
        case .door(let run): branch = nil; number = nil; note = run.folderNote; command = run.command
        case .task(let task): branch = task.branch; number = task.taskNumber; note = task.noBranchNote; command = nil
        case .scratch: branch = nil; number = nil; note = nil; command = nil
        case .job: return
        }
        let location = worktreeLocation
        let title = row.title
        Task {
            await model.sessions.start(taskID: id, branch: branch, taskNumber: number,
                                       noBranchNote: note, worktreeLocation: location, title: title)
            guard case .running(let folder) = model.sessions.state(for: id) else { return }
            terminals.start(taskID: id, folder: folder.url)
            if let command { terminals.send(command + "\n", to: id) }
        }
    }

    @ViewBuilder private var pane: some View {
        switch row.kind {
        case .job(let job):
            JobPane(job: job, answer: $answer) { jobs?.answer($0, to: job.id) }
        case .door(let run):
            ShellPane(sessions: model.sessions, id: run.id, folderNote: run.folderNote,
                      command: run.command, startTitle: "Start run", showsStop: false, showsStart: false)
        case .task(let task):
            ShellPane(sessions: model.sessions, id: task.id, branch: task.branch,
                      taskNumber: task.taskNumber, folderNote: task.noBranchNote, startTitle: "Start shell",
                      showsStop: false, showsStart: false)
        case .scratch:
            ShellPane(sessions: model.sessions, id: row.id, startTitle: "Start terminal", showsStop: false, showsStart: false)
        }
    }
}

/// A door this window started, a task's own session, or a run with no terminal at all. One list: a background
/// run is still a run, and it had no surface anywhere in the app — you pressed a button, a job started, and
/// nothing on screen ever mentioned it again.
struct SessionRow: Identifiable {
    enum Kind { case door(DoorRun), task(DeskTask), scratch, job(BackgroundJob) }

    let id: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let kind: Kind

    @MainActor
    static func all(in model: ProjectWindowModel, jobs: JobRegistry? = nil) -> [SessionRow] {
        let doorIDs = Set(model.runs.runs.map(\.id))
        let doors = model.runs.runs.map { run in
            SessionRow(id: run.id, title: run.title,
                       subtitle: "\(run.agent) · \(RunLabel.label(for: model.sessions.state(for: run.id)).label)",
                       isLive: model.sessions.state(for: run.id).isLive, kind: .door(run))
        }
        let tasks = model.sessions.activeTaskIDs.filter { !doorIDs.contains($0) }.compactMap { id -> SessionRow? in
            guard let task = model.task(id) else { return nil }
            return SessionRow(id: id, title: task.title,
                              subtitle: model.sessions.purpose(for: id) == .agent ? "Agent" : "Terminal",
                              isLive: model.sessions.state(for: id).isLive, kind: .task(task))
        }
        let scratch = model.scratchTerminals.map { id in
            SessionRow(id: id, title: "Terminal \(id.replacingOccurrences(of: "term:", with: ""))",
                       subtitle: RunLabel.label(for: model.sessions.state(for: id)).label,
                       isLive: model.sessions.state(for: id).isLive, kind: .scratch)
        }
        var background: [SessionRow] = []
        if let jobs, case .local(let path) = model.ref {
            background = jobs.jobs(in: path).map { job in
                SessionRow(id: job.id, title: job.title, subtitle: "\(job.agent) · \(job.state.label)",
                           isLive: job.state.isLive, kind: .job(job))
            }
        }
        return background + doors + tasks + scratch
    }
}
