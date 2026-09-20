import DeskCore
import SwiftUI

/// Every session this window is running, as tabs across the top with the chosen one open below. The **only**
/// host of a live terminal (ADR 0026): a terminal is an NSView and can live in exactly one view hierarchy, so a
/// second surface showing the same one draws an empty frame while the first keeps it.
///
/// Tabs rather than the accordion that was here: sessions are switched between far more often than they are
/// compared, and a tab bar spends one row on the whole list instead of one row each. What that buys is the
/// pane below — full height, its transcript scrolling, and its composer along the bottom where every other
/// input in the app is. Only the tab in front is built, so the one-host rule is the layout's doing rather than
/// something the next surface has to remember.
struct TerminalsScreen: View {
    @Bindable var model: ProjectWindowModel
    /// Which tab is in front. It is real state, not `selection ?? firstLive`: a derived selection re-opened
    /// whatever it fell back to the moment the chosen one was closed, and the click did nothing, every time.
    @State private var selection: Selection = .starter
    @State private var hasChosen = false
    /// What was live when the app was last killed (ADR 0031). Records, not sessions: nothing here is running.
    @State private var recovered: [JournalRecord] = []
    /// Where a new terminal's worktree would go, read here because opening one starts its shell at once.
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @Environment(\.terminals) private var terminals

    /// What is in front: one of the sessions, or the starter — the pane a session is typed into being in,
    /// which is what a window with no sessions opens on. The starter has no tab of its own: New session in the
    /// header opens a session outright, and the starter is where the screen lands when there is no session to show.
    private enum Selection: Hashable {
        case starter
        case session(String)
    }

    private var rows: [SessionRow] { SessionRow.all(in: model, jobs: jobs) }
    /// Nil for a sample, which has no folder to have written anything in.
    private var journal: RunJournal? { model.sessions.journal }

    /// The session the tab in front names, or nil for the starter — and nil too for a tab whose session has
    /// just gone, until the change below moves the selection off it.
    private var selectedRow: SessionRow? {
        guard case .session(let id) = selection else { return nil }
        return rows.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The shared header first, like every tab (ADR 0046 decision 14), then the sessions as its second row.
            // New session is the header's one primary button; the "+" that sat at the end of the tabs was the same
            // action a second time, so it went.
            header
            tabBar
            // Above the open session, because it is what happened while the app was gone and the open one is now.
            if !recovered.isEmpty { recoveredSection }
            pane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        .onAppear(perform: syncSelection)
        .onAppear(perform: loadRecovered)
        // Initial too: the menu can ask from another screen, before this one exists to hear it change.
        .onChange(of: model.terminalAwaitingStart, initial: true) { _, id in
            guard let id else { return }
            model.terminalAwaitingStart = nil
            hasChosen = true
            selection = .session(id)
            startTerminal(id)
        }
        .onChange(of: model.selectedSessionID) { _, id in
            guard let id else { return }
            hasChosen = true
            selection = .session(id)
        }
        // A session can leave the list without being closed from here — a door run cleared, a job removed in
        // another screen. The tab in front cannot point at nothing, so it falls to whatever is left.
        .onChange(of: rows.map(\.id)) { _, ids in
            guard case .session(let id) = selection, !ids.contains(id) else { return }
            selection = ids.first.map(Selection.session) ?? .starter
        }
    }

    /// A new scratch session, in front. Its shell is started here, not by a button in its pane: opening one and
    /// being told "Not started" made every new terminal a two-click session whose second click was never a choice.
    private func open() {
        hasChosen = true
        let id = model.newTerminal()
        selection = .session(id)
        startTerminal(id)
    }

    /// The same start the pane's Start button made for a scratch row — the registry resolves the folder, the
    /// project root for a scratch session, and the shell opens in it. The menu item is disabled under a
    /// refusal, but the guard stays: a menu built a moment before the registry changed its mind still lands here.
    private func startTerminal(_ id: String) {
        guard model.sessions.startRefusal(for: .shell) == nil, let terminals else { return }
        let location = worktreeLocation
        let title = "Terminal \(id.replacingOccurrences(of: "term:", with: ""))"
        Task {
            await model.sessions.start(taskID: id, branch: nil, taskNumber: nil,
                                       noBranchNote: nil, worktreeLocation: location, title: title)
            guard case .running(let folder) = model.sessions.state(for: id) else { return }
            terminals.start(taskID: id, folder: folder.url)
        }
    }

    private var header: some View {
        let live = rows.filter(\.isLive).count
        let refusal = model.sessions.startRefusal(for: .shell)
        return ScreenHeader(.terminals) {
            Text(rows.isEmpty ? "None open" : "\(live) running · \(rows.count) open")
        } tools: {
            Button("New session", action: open)
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                .disabled(refusal != nil)
                .help(refusal ?? "A login shell at the project root")
        }
    }

    // MARK: - The tabs

    /// The sessions across the top, in the order the list has always had them; New session is in the
    /// header above. It scrolls sideways rather than shrinking: a tab narrow enough to fit twelve of them
    /// names none of them.
    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(rows) { row in
                    SessionTab(row: row,
                               isSelected: selection == .session(row.id), close: tabClose(for: row)) {
                        hasChosen = true
                        selection = .session(row.id)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
        // One row, stated: the bar is the list of sessions and never a second pane, however many there are.
        .frame(height: DeskMetric.screenBarHeight)
        .background(DeskColor.canvas)   // the header's second row (ADR 0046 decision 14)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// What the × on a tab does: the same action that row's header carried before the tabs, under a smaller
    /// glyph. Nothing here means anything new — a live run is stopped, a finished background run is taken off
    /// the list, a scratch session is closed — and a row with none of those, a door or a task that is not
    /// running, gets no × at all rather than one that would have to invent a meaning.
    private func tabClose(for row: SessionRow) -> TabClose? {
        func closing(_ help: String, isEnabled: Bool = true, _ run: @escaping () -> Void) -> TabClose {
            TabClose(help: help, isEnabled: isEnabled) {
                let fallback = neighbour(of: row.id)
                run()
                // Stop leaves the row listed and ended; only a close or a remove takes it away, and only then
                // does the tab in front have to move.
                guard selection == .session(row.id), !rows.contains(where: { $0.id == row.id }) else { return }
                selection = fallback
            }
        }
        if case .job(let job) = row.kind {
            return job.state.isLive
                ? closing("Stops this run") { jobs?.stop(job.id) }
                : closing("Takes the finished run off this list") { jobs?.remove(job.id) }
        }
        // A project run stops through its own stop rows before the shell is ended; a plain end would skip them.
        if case .projectRun = row.kind {
            if row.isLive {
                return closing("Stops this run") { if let terminals { model.stopProjectRun(sessionID: row.id, terminals: terminals) } }
            }
            return closing("Takes the finished run off this list") { model.projectRuns.forget(sessionID: row.id) }
        }
        if row.isLive { return closing("Stops this session") { terminals?.end(taskID: row.id) } }
        guard case .scratch = row.kind else { return nil }
        return closing("Remove this terminal from the list") { model.closeTerminal(row.id) }
    }

    /// Which tab takes the front when this one goes: the one after it, else the one before it, else the starter.
    private func neighbour(of id: String) -> Selection {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return .starter }
        let next = rows[(index + 1)...].first ?? rows[..<index].last
        return next.map { Selection.session($0.id) } ?? .starter
    }

    // MARK: - The one open session

    /// The body: the session in front, and nothing of any other. A pane per session is exactly what made a
    /// second terminal draw an empty frame, so there is one here — given the session's own identity, so a
    /// draft and a poll belong to the session shown and not to the place in the layout.
    @ViewBuilder private var pane: some View {
        if let row = selectedRow {
            SessionPane(model: model, row: row)
                .id(row.id)
        } else {
            starter
        }
    }

    // MARK: - Nothing open

    /// The starter: the pane a window with no sessions opens on, saying what a session here is.
    private var starter: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Start a session")
                    Text("Start a task from the board, run a door from Findings, Ideation or Roadmap, or open a terminal here. Whether it takes a terminal or runs in the background, it is a session here.")
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    // Only while there is nothing to switch to: with sessions listed above, the board is one
                    // click away in the sidebar and this would be a second door to it.
                    if rows.isEmpty {
                        Button("Go to the board") { model.go(.board) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.canvas)
    }

    /// Which tab is in front on arriving. A card or a door start lands on that session; otherwise the first
    /// live one, then the first there is, and the starter when there is no session to land on at all.
    private func syncSelection() {
        guard !hasChosen else { return }
        let landing = model.selectedSessionID.flatMap { id in rows.contains { $0.id == id } ? id : nil }
            ?? rows.first(where: \.isLive)?.id ?? rows.first?.id
        selection = landing.map(Selection.session) ?? .starter
    }

    /// A section rather than tabs of its own: these are records of runs the app died under, and a tab would
    /// offer to open something that is not there. It sits above the open session — it is what happened while
    /// the app was gone, and the session below is now — and goes as each record is answered.
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
        .padding(12)
        .background(DeskColor.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
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

    /// A shell in the task's own worktree — what a recovered run leaves you: the folder it was working in, open,
    /// with its branch checked out. The agent's session is gone; the work it left on disk is not.
    private func openTerminal(for task: DeskTask) {
        guard let terminals else { return }
        hasChosen = true
        if model.sessions.state(for: task.id).isLive {
            selection = .session(task.id)
            return
        }
        let location = worktreeLocation
        Task {
            await model.sessions.start(taskID: task.id, branch: task.branch, taskNumber: task.taskNumber,
                                       noBranchNote: task.noBranchNote, worktreeLocation: location,
                                       title: task.title, baseRef: task.baseRef)
            guard case .running(let folder) = model.sessions.state(for: task.id) else { return }
            terminals.start(taskID: task.id, folder: folder.url)
            // Selected only now: a tab for a session that does not exist yet is dropped by the bar's own
            // "selection must name a row" rule, which left the click looking like nothing happened.
            selection = .session(task.id)
            model.selectedSessionID = task.id
        }
    }

    /// The honest second best. It never claims the old conversation is back: a session is re-opened for the
    /// task, or the door is run again from its start.
    private func handoff(for record: JournalRecord) -> RecoveredTile.Handoff? {
        switch record.kind {
        case .terminalSession:
            // A `/dev` run is recorded under its run id (`task:776`), the card under its number (`776`). Matching
            // only the card's id left a recovered run with nothing but Dismiss.
            guard let task = model.tasks.first(where: { $0.id == record.id || DoorRuns.id(for: $0) == record.id })
            else { return nil }
            return RecoveredTile.Handoff(title: "Open a terminal",
                                         help: "Opens a shell in this task's worktree, where the run was working. It starts fresh — the agent's own conversation is not restored.") {
                openTerminal(for: task)
                dismiss(record)
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

/// What the × on a tab does, and what it says it does. The screen builds one per session out of that
/// session's own action, so the glyph never means more than the button it stands in for.
private struct TabClose {
    let help: String
    var isEnabled = true
    let run: () -> Void
}

/// One session across the top: how it is doing, what it is called, and the × that stops or closes it. The ×
/// appears on hover and stays on the tab in front — a row of crosses reads as a list of things to delete
/// rather than as the sessions themselves — and it holds its place either way, so no tab resizes under the
/// pointer.
private struct SessionTab: View {
    let row: SessionRow
    let isSelected: Bool
    /// Nil where the session has nothing to stop or close; the tab is then a name and a light, which is what
    /// a door or a task that is not running has always been here.
    let close: TabClose?
    let select: () -> Void
    @State private var isHovered = false

    private var dotTone: StatusTone { row.isLive ? .running : .ended }

    private var showsClose: Bool { close != nil && (isSelected || isHovered) }

    var body: some View {
        VStack(spacing: 0) {
            // Selecting is its own button and the × is its sibling. One button wrapping the other swallows the
            // inner one's clicks — the same way the card's outer Button ate its own Start, and it was reported
            // the same way: "stop is not working".
            HStack(spacing: 6) {
                Button(action: select) {
                    HStack(spacing: 7) {
                        StatusDot(tone: dotTone, pulses: row.isLive)
                        Text(row.title)
                            .font(DeskFont.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? DeskColor.ink : DeskColor.mutedInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 170, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title), \(row.subtitle)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                if let close {
                    Button(action: close.run) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DeskColor.mutedInk)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!close.isEnabled)
                    .opacity(showsClose ? (close.isEnabled ? 1 : 0.4) : 0)
                    .allowsHitTesting(showsClose)
                    .help(close.help)
                    .accessibilityLabel("Close \(row.title)")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, close == nil ? 10 : 4)
            .frame(height: 30)
            // The same underline a dialog's tabs carry, over the same fill a hovered secondary button takes.
            Rectangle()
                .fill(isSelected ? DeskColor.accent : Color.clear)
                .frame(height: 2)
        }
        .background(isSelected || isHovered ? DeskColor.headerFill : Color.clear)
        .onHover { isHovered = $0 }
    }
}

/// The session in front: what it is doing and its body — the terminal as it is, or a background run's log.
/// Its name and its × belong to the tab above, and are not said twice here.
private struct SessionPane: View {
    let model: ProjectWindowModel
    let row: SessionRow
    @Environment(\.terminals) private var terminals
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @State private var answer = ""

    /// A scratch session is its body alone. Its terminal started the moment it was opened, so a header would
    /// carry a subtitle the tab already says and no button at all.
    private var showsHeader: Bool {
        switch row.kind {
        // A project run started as the toolbar's play was pressed; running it again is that same button.
        case .scratch, .projectRun: return false
        case .door, .task, .job: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Rectangle().fill(DeskColor.divider).frame(height: 1)
            }
            // The session takes everything left of the screen, which is what pins its input: the transcript
            // inside it scrolls, and the composer under that sits on the bottom edge instead of being scrolled
            // away with the answer it is replying to.
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What a tab cannot carry: what the session is doing, and Start — a door or a task is a prepared run,
    /// and starting one stays the user's own act. Stop, Close and Remove are the tab's × — the same actions
    /// this header used to hold — so they are not offered a second time here.
    private var header: some View {
        HStack(spacing: 8) {
            Text(row.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
            // A background run has no clock of its own. This one ticks by itself, so a run that has been
            // "running" for twenty minutes reads as one.
            if case .job(let job) = row.kind, job.state.isLive {
                Text(job.startedAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let target = worktreeTarget, model.projectRuns.canRun {
                Button {
                    guard let terminals else { return }
                    model.requestProjectRun(target: target, terminals: terminals, worktreeLocation: worktreeLocation)
                } label: {
                    Label("Run \(target.branch)", systemImage: "play.fill")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .disabled(terminals == nil)
                .help("Runs \(model.projectRuns.plan.defaultConfiguration?.name ?? "the project") in this session's worktree, on \(target.branch)")
            }
            if startsHere {
                Button(startTitle) { start() }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .mini))
                    .disabled(terminals == nil)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(DeskColor.headerFill)
    }

    /// This session's own worktree, when it has one: a task started in a folder that is not the project folder.
    private var worktreeTarget: RunTarget? {
        guard case .task = row.kind, let root = model.projectRoot else { return nil }
        switch model.sessions.state(for: row.id) {
        case .running(let folder), .ended(let folder, _):
            guard folder.url.standardizedFileURL != root.standardizedFileURL else { return nil }
            return RunTarget(folder: folder.url, branch: RunTarget.branch(in: folder.url), isProjectFolder: false)
        default:
            return nil
        }
    }

    /// A live session has nothing to start and a background run has no shell at all: Start is for a door or
    /// a task that is not running. A scratch session never shows this header, so it is never asked.
    private var startsHere: Bool {
        if case .job = row.kind { return false }
        return !row.isLive
    }

    private var startTitle: String {
        if case .ended = model.sessions.state(for: row.id) { return "Start again" }
        switch row.kind {
        case .door: return "Start run"
        // A scratch session started as it opened, and a background run has no shell to start; neither shows
        // this header, so neither reads this title.
        case .task, .scratch, .job, .projectRun: return "Start"
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
        var freshBase = false
        var runTask: Int?
        switch row.kind {
        case .door(let run): branch = nil; number = nil; note = run.folderNote; command = run.command; freshBase = run.freshBase; runTask = run.taskNumber
        case .task(let task): branch = task.branch; number = task.taskNumber; note = task.noBranchNote; command = nil
        case .scratch, .job, .projectRun: return
        }
        let location = worktreeLocation
        let title = row.title
        Task {
            await model.sessions.start(taskID: id, branch: branch, taskNumber: number,
                                       noBranchNote: note, worktreeLocation: location, title: title)
            guard case .running(let folder) = model.sessions.state(for: id) else { return }
            terminals.start(taskID: id, folder: folder.url)
            guard let command else { return }
            var preamble = ""
            if freshBase || runTask != nil, case .local(let path) = model.ref {
                let worktrees = FreshBaseWorktree(projectRoot: URL(fileURLWithPath: path, isDirectory: true), worktreeLocation: location)
                let fresh = if let runTask { await worktrees.prepareTask(number: runTask) } else { await worktrees.prepare(door: id) }
                if fresh.created {
                    preamble = "cd \(ShellQuote.single(fresh.url.path)) && "
                } else if let reason = fresh.note {
                    preamble = "echo \(ShellQuote.single(reason)); "
                }
            }
            // A login shell reads nothing until it has drawn its first prompt; typed sooner the line is swallowed,
            // and zsh mid-setup answers with "error on TTY read: invalid argument" and exits 1 (seen 2026-09-20).
            // The pane's own start has always waited; this one did not.
            try? await Task.sleep(for: .milliseconds(700))
            // Through sendCommand, not send: a plain send typed the agent without its hooks, so it never notified.
            terminals.sendCommand(command, to: id, preamble: preamble)
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
            // The shell started as the session was opened, so this pane hosts it running. No Start: a session
            // that somehow is not says so through the pane's own message.
            ShellPane(sessions: model.sessions, id: row.id, showsStop: false, showsStart: false)
        case .projectRun:
            // The run's shell, hosted exactly as a scratch terminal's is: it started when play was pressed,
            // and its stop is the tab's ×, which runs the configuration's stop rows first.
            ShellPane(sessions: model.sessions, id: row.id, showsStop: false, showsStart: false)
        }
    }
}

/// A door this window started, a task's own session, or a run with no terminal at all. One list: a background
/// run is still a run, and it had no surface anywhere in the app — you pressed a button, a job started, and
/// nothing on screen ever mentioned it again.
struct SessionRow: Identifiable {
    /// `projectRun` is the project running itself from the toolbar (`run:` ids): a shell like a scratch
    /// session's, but stopped through its configuration's stop rows rather than by ending the shell outright.
    enum Kind { case door(DoorRun), task(DeskTask), scratch, job(BackgroundJob), projectRun }

    let id: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let kind: Kind

    @MainActor
    static func all(in model: ProjectWindowModel, jobs: JobRegistry? = nil) -> [SessionRow] {
        let doorIDs = Set(model.runs.runs.map(\.id))
        // A live session whose agent has ended its turn says so: "Running" on one waiting for a message was the
        // same word for working and for waiting.
        func state(_ id: String) -> String {
            model.sessions.state(for: id).isLive && model.waitingSessions.contains(id)
                ? "Waiting for you" : RunLabel.label(for: model.sessions.state(for: id)).label
        }
        let doors = model.runs.runs.map { run in
            SessionRow(id: run.id, title: run.title,
                       subtitle: "\(run.agent) · \(state(run.id))",
                       isLive: model.sessions.state(for: run.id).isLive, kind: .door(run))
        }
        let tasks = model.sessions.activeTaskIDs.filter { !doorIDs.contains($0) }.compactMap { id -> SessionRow? in
            guard let task = model.task(id) else { return nil }
            return SessionRow(id: id, title: task.title,
                              subtitle: (model.sessions.purpose(for: id) == .agent ? "Agent" : "Terminal")
                                  + (model.waitingSessions.contains(id) ? " · Waiting for you" : ""),
                              isLive: model.sessions.state(for: id).isLive, kind: .task(task))
        }
        let scratch = model.scratchTerminals.map { id -> SessionRow in
            let number = id.replacingOccurrences(of: "term:", with: "")
            return SessionRow(id: id, title: "Terminal \(number)",
                              subtitle: "Terminal · \(state(id))",
                              isLive: model.sessions.state(for: id).isLive, kind: .scratch)
        }
        var background: [SessionRow] = []
        if let jobs, case .local(let path) = model.ref {
            background = jobs.jobs(in: path).map { job in
                SessionRow(id: job.id, title: job.title, subtitle: "\(job.agent) · \(job.state.label)",
                           isLive: job.state.isLive, kind: .job(job))
            }
        }
        // The project's own runs, titled as they were when play was pressed: the plan may have renamed the
        // configuration since, and the row must still say what is running.
        let projectRuns = model.projectRuns.sessionIDs.map { id -> SessionRow in
            let state = model.sessions.state(for: id)
            return SessionRow(id: id, title: model.projectRuns.title(sessionID: id),
                              subtitle: "Project run · \(RunLabel.label(for: state).label)",
                              isLive: state.isLive, kind: .projectRun)
        }
        return background + doors + tasks + scratch + projectRuns
    }
}
