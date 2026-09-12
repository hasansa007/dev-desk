import DeskCore
import SwiftUI

/// Everything this window has live — the doors it started, and every task's terminal and agent. It is the
/// window's bottom edge, where a Mac app keeps its output, and never a window floating over the work.
///
/// It listed door runs only, so a panel titled Runs said "Nothing running" while an agent worked and the
/// board's own header counted it. A run you cannot see is a run you cannot stop.
struct RunsPanel: View {
    @Bindable var model: ProjectWindowModel
    @Environment(\.shellTerminals) private var terminals
    @Environment(\.agentTerminals) private var agents
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var answers: [String: String] = [:]

    private var selected: DoorRun? {
        model.runs.selectedID.flatMap { model.runs.run($0) } ?? model.runs.runs.first
    }

    /// A task's own terminal or agent, which lives in that task's dialog. The panel lists it and can stop it;
    /// it does not re-host the terminal, because one NSView cannot be in two view hierarchies at once.
    private struct SessionRow: Identifiable {
        let id: String
        let taskID: String
        let title: String
        let kind: TaskActivity
        let state: ShellSessionState
    }

    private var sessionRows: [SessionRow] {
        let doorIDs = Set(model.runs.runs.map(\.id))
        func rows(_ sessions: ShellSessions, kind: TaskActivity) -> [SessionRow] {
            sessions.activeTaskIDs.filter { !doorIDs.contains($0) }.map { taskID in
                SessionRow(id: "\(kind.rawValue):\(taskID)", taskID: taskID,
                           title: model.task(taskID)?.title ?? taskID,
                           kind: kind, state: sessions.state(for: taskID))
            }
        }
        return rows(model.agentSessions, kind: .agent) + rows(model.shellSessions, kind: .shell)
    }

    private var isEmpty: Bool { model.runs.runs.isEmpty && sessionRows.isEmpty && (jobs?.jobs.isEmpty ?? true) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isEmpty {
                EmptyStateView(title: "Nothing running",
                               message: "Run survey in Findings, or Start task on a card, and it appears here.")
            } else {
                runList
                if let selected {
                    Rectangle().fill(DeskColor.divider).frame(height: 1)
                    ShellPane(sessions: model.shellSessions, id: selected.id, folderNote: selected.folderNote,
                              command: selected.command, startTitle: "Start run")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.border).frame(height: 1) }
        .onChange(of: endedRuns) { _, _ in Task { await model.load() } }
    }

    /// A finished run has written whatever it was going to write, so the project is read again.
    private var endedRuns: Int {
        model.runs.runs.filter {
            if case .ended = model.shellSessions.state(for: $0.id) { return true }
            return false
        }.count
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Runs").font(.system(size: 13, weight: .semibold)).foregroundStyle(DeskColor.ink)
            Spacer(minLength: 8)
            Button("Close") { model.toggleRuns() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// Scrolls: a job row carries a log box and, when it is asking, a banner and a field. Three of them used to
    /// push Stop and Answer past the panel's edge with no way to reach them.
    private var runList: some View {
        ScrollView {
            VStack(spacing: 0) {
            ForEach(model.runs.runs) { run in
                runRow(run)
            }
            ForEach(sessionRows) { row in
                sessionRow(row)
            }
            if let jobs {
                ForEach(jobs.jobs) { job in
                    jobRow(job, registry: jobs)
                }
            }
            }
        }
        .frame(maxHeight: 260)
    }

    /// A background run has no terminal, so the row is where it lives: its log, its Stop, and — when it stopped
    /// needing an answer — the box that answers it and resumes the same session (ADR 0025).
    @ViewBuilder private func jobRow(_ job: BackgroundJob, registry: JobRegistry) -> some View {
        let tone: StatusTone = {
            switch job.state {
            case .starting: return .info
            case .running: return .running
            case .asking: return .waiting
            case .ended(_, let failed): return failed ? .failed : .ended
            }
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(tone: tone, pulses: job.state.isLive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(DeskFont.body.weight(.semibold))
                        .foregroundStyle(DeskColor.ink)
                        .lineLimit(1)
                    Text("\(job.agent) · in the background · \(job.state.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                Spacer(minLength: 4)
                if job.state.isLive {
                    Button("Stop") { registry.stop(job.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help("End this background run")
                } else {
                    Button("Remove") { registry.remove(job.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                }
            }
            if !job.log.isEmpty {
                ScrollView {
                    Text(job.log.joined(separator: "\n"))
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            }
            if case .asking(let question) = job.state {
                NoticeBanner(tone: .waiting, title: "This run needs an answer", message: question, style: .compact)
                HStack(spacing: 8) {
                    TextField("Your answer", text: Binding(get: { answers[job.id] ?? "" },
                                                           set: { answers[job.id] = $0 }))
                        .textFieldStyle(.plain)
                        .font(DeskFont.body)
                        .padding(8)
                        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                    Button("Answer and continue") {
                        let text = (answers[job.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        answers[job.id] = ""
                        registry.answer(text, to: job.id)
                    }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .disabled((answers[job.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
    }

    /// A terminal or an agent someone started from a task's dialog. Open goes to it; Stop ends it here, which is
    /// what the list was missing — Remove only ever dropped a row and left the process running.
    private func sessionRow(_ row: SessionRow) -> some View {
        let state = Self.label(for: row.state)
        return HStack(spacing: 8) {
            StatusDot(tone: state.tone, pulses: state.pulses)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                Text("\(row.kind.label) · \(state.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 4)
            Button("Open") {
                model.openTask(row.taskID)
                model.tab = row.kind == .agent ? .agent : .shell
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            Button("Stop") { stop(row) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .disabled(!state.isLive)
                .help(state.isLive ? "End this session and its process" : "This session has already ended")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
    }

    /// SIGHUP then SIGKILL, through the registry that owns the session — the same path the pane's own Stop takes.
    private func stop(_ row: SessionRow) {
        switch row.kind {
        case .agent: agents?.end(taskID: row.taskID)
        case .shell, .run: terminals?.end(taskID: row.taskID)
        }
    }

    private func runRow(_ run: DoorRun) -> some View {
        let state = Self.label(for: model.shellSessions.state(for: run.id))
        let isSelected = run.id == selected?.id
        return Button { model.runs.selectedID = run.id } label: {
            HStack(spacing: 8) {
                StatusDot(tone: state.tone, pulses: state.pulses)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.title)
                        .font(DeskFont.body.weight(.semibold))
                        .foregroundStyle(DeskColor.ink)
                    Text("\(run.agent) · \(state.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                Spacer(minLength: 4)
                if state.isLive {
                    Button("Stop") { terminals?.end(taskID: run.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help("End this run and its shell")
                } else {
                    Button("Remove") { model.runs.remove(run.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help("Remove this run from the list")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

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
            runsOpen = isRunLive(runID) ? true : runsOpen
            runs.selectedID = isRunLive(runID) ? runID : runs.selectedID
            return
        }
        runs.add(DoorRun(id: runID, title: title, agent: agent, command: command,
                         folderNote: folderNote ?? "a door reads the whole project, not one task's branch."))
        runsOpen = true
    }

    /// Approving an item files it through `dev:create-issue` rather than writing the issue here, so the door's
    /// checks and this repository's labels still apply to anything that reaches the backlog.
    func fileFromReport(itemID: String, description: String, agent: String) {
        prepareRun(door: "create-issue", title: "File \(itemID)", agent: agent, arguments: [description],
                   id: DoorRuns.id(door: "create-issue:\(itemID)"),
                   folderNote: "filing reads the tracker, so it runs at the project root.")
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
