import AppKit
import DeskCore
import SwiftUI

struct BoardScreen: View {
    @Bindable var model: ProjectWindowModel
    /// Done only grows, and merged work is the one column you never act on: it is a strip at the board's edge
    /// until you ask for it (the Focus layout, 2026-09-20), which is what gives In progress the width.
    @AppStorage("workHidesDone") private var hidesDone = true

    /// The columns you scan; In progress takes everything they leave, so the run you are watching is the
    /// widest thing on screen. `DeskMetric.boardColumnWidth` still sizes a board that is all columns.
    static let sideColumnWidth: CGFloat = 248
    /// What a side column may be squeezed to before In progress is asked to give up any width. With the
    /// filter panel open on a 1100 pt window the fixed 248s left In progress 48 pt — a sliver where the
    /// widest thing on screen was supposed to be (2026-09-20, on screen).
    static let sideColumnMinWidth: CGFloat = 186
    /// Below this In progress stops being the focus of anything, so the board goes back to equal columns
    /// you scroll sideways rather than drawing four slivers.
    static let focusMinWidth: CGFloat = 300
    /// Done, closed: a count and its name turned on its side.
    static let doneStripWidth: CGFloat = 52

    var body: some View {
        // Work (ADR 0046 decisions 13, 14): the one header and the filters span the tab; below them the milestones on
        // the left choose what the Board on the right shows.
        // The shared filter panel on the left, its header level with the tab's (ADR 0046 decision 18).
        HStack(spacing: 0) {
            filterPanel
            VStack(spacing: 0) {
                header
                boardArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
    }

    // MARK: - Filters

    /// Milestone is a filter group like Tag (ADR 0046 decision 18): none on is every milestone, the Working now one
    /// carries Now, and right-click makes another one Working now. Run roadmap sits on the group it fills.
    private var filterPanel: some View {
        let filter = model.taskFilter
        return FilterPanel(
            title: "Filters", guide: WorkGuides.milestones, storageKey: "work",
            groups: [milestoneGroup,
                     FilterGroup(key: "work.priority", title: "Priority", kind: .filter,
                                 options: TaskFilter.priorityOrder.map { p in
                                     FilterOption(id: p, label: p, isOn: filter.priorities.contains(p), tone: TaskCard.priorityTone(p),
                                                  count: "\(model.facetCount(.priority) { $0.priority == p })")
                                 } + [FilterOption(id: TaskFilter.unprioritised, label: "None",
                                                   isOn: filter.priorities.contains(TaskFilter.unprioritised),
                                                   count: "\(model.facetCount(.priority) { $0.priority == nil })")],
                                 toggle: { toggle(\.priorities, $0) }, guide: WorkGuides.priority),
                     FilterGroup(key: "work.type", title: "Type", kind: .filter,
                                 options: TaskKind.allCases.map { kind in
                                     FilterOption(id: kind.rawValue, label: kind.rawValue, isOn: filter.kinds.contains(kind),
                                                  count: "\(model.facetCount(.kind) { $0.kind == kind })")
                                 },
                                 toggle: { id in if let kind = TaskKind(rawValue: id) { toggle(\.kinds, kind) } },
                                 guide: WorkGuides.type),
                     FilterGroup(key: "work.tag", title: "Tag", kind: .filter,
                                 options: TaskFilter.tagLabels.map { tag in
                                     FilterOption(id: tag, label: tag.capitalized, isOn: filter.tags.contains(tag),
                                                  count: "\(model.facetCount(.tag) { $0.labels.contains(tag) })")
                                 },
                                 toggle: { toggle(\.tags, $0) }, guide: WorkGuides.tag)],
            clear: (filter.summary, filter.activeCount, { model.taskFilter = TaskFilter() }))
    }

    private var milestoneGroup: FilterGroup {
        let keys = model.effectiveWorkScope.keys
        let rows = model.milestoneRows.filter { !ProjectWindowModel.isFinished($0) || keys.contains($0.title ?? "") }
        let filter = model.taskFilter
        func count(_ milestone: String?) -> String {
            "\(model.tasks.filter { $0.issueNumber != nil && $0.column != .done && $0.milestone == milestone && filter.matches($0) }.count)"
        }
        let options = rows.map { row -> FilterOption in
            guard let title = row.title else {
                return FilterOption(id: TaskFilter.noMilestone, label: "No milestone", isOn: keys.contains(TaskFilter.noMilestone),
                                    count: count(nil))
            }
            return FilterOption(id: title, label: Self.shortName(title), isOn: keys.contains(title),
                                count: count(title), badge: row.isWorkingNow ? "Now" : nil, help: title,
                                actions: row.isWorkingNow ? [] : [FilterAction(title: "Make Working now") {
                                    Task { await model.moveToTopOfPlan(title) }
                                }])
        }
        return FilterGroup(key: "work.milestone", title: "Milestone", kind: .filter, options: options,
                           toggle: { model.toggleWorkMilestone($0) }, guide: WorkGuides.milestone,
                           accessory: AnyView(DoorRunControl(model: model, door: "roadmap", title: "Run roadmap", size: .small)),
                           maxLabelWidth: 190)
    }

    /// "Money integrity — nothing billed…" → "Money integrity": the part before the dash names it; hover has the rest.
    static func shortName(_ title: String) -> String {
        for separator in [" — ", " – ", " - "] {
            if let range = title.range(of: separator) { return String(title[..<range.lowerBound]) }
        }
        return title
    }

    private func toggle<T: Hashable>(_ path: WritableKeyPath<TaskFilter, Set<T>>, _ value: T) {
        var f = model.taskFilter
        if f[keyPath: path].contains(value) { f[keyPath: path].remove(value) } else { f[keyPath: path].insert(value) }
        model.taskFilter = f
    }

    /// The shared header (ADR 0046 decision 14): the selected milestone and its progress, then search and New task.
    private var header: some View {
        ScreenHeader(.board) {
            Text(scopeStatus)
        } tools: {
            searchField
            newTaskButton
        }
    }

    /// The milestone, then — while any filter is on — what is on and how much it leaves: "P0, Bug · 1 of 11 shown".
    private var scopeStatus: String {
        guard model.taskFilter.activeCount > 0 else { return milestoneStatus }
        let tally = model.workFilterTally
        return "\(milestoneTitle) · \(model.taskFilter.summary) · \(tally.shown) of \(tally.total) shown"
    }

    private var milestoneTitle: String {
        switch model.effectiveWorkScope {
        case .all: return "All milestones"
        case .noMilestone: return "No milestone"
        case .milestone(let title): return title
        case .several(let keys): return keys.map { $0 == TaskFilter.noMilestone ? "No milestone" : Self.shortName($0) }.sorted().joined(separator: ", ")
        }
    }

    private var milestoneStatus: String {
        let rows = model.milestoneRows
        switch model.effectiveWorkScope {
        case .all:
            return "All milestones · \(rows.reduce(0) { $0 + $1.tasks.count }) open"
        case .noMilestone:
            return "No milestone · \(rows.first { $0.title == nil }?.tasks.count ?? 0) open"
        case .milestone(let title):
            guard let row = rows.first(where: { $0.title == title }) else { return title }
            return "\(title) · \(row.closed) of \(row.total) done"
        case .several:
            return "\(milestoneTitle) · \(model.workFilterTally.total) open"
        }
    }

    /// One New task, in the header — not a button at the foot of a column (ADR 0046). It lands in the milestone
    /// selected on the left (the sheet starts there), and in Next up when that is the Working now milestone.
    private var newTaskButton: some View {
        let noFolder = model.snapshot?.repositoryRoot == nil
        let column: BoardColumn = model.firstWorkColumnTitle == BoardColumn.readyForDev.title
            && model.effectiveWorkScope != .all ? .readyForDev : .backlog
        return Button("New task") { model.present(.addTask(column.rawValue)) }
            .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
            .disabled(noFolder)
            .help(noFolder ? "This project has no folder on disk, so there is nowhere to write a task"
                           : "Add a task — it is filed where the tracker is, in the milestone selected on the left")
    }

    private var searchField: some View {
        TextField("Search tasks", text: $model.searchText)
            .textFieldStyle(.plain)
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.ink)
            .padding(.horizontal, 10)
            .frame(width: 180, alignment: .leading)
            .controlChrome()
    }

    @ViewBuilder
    private var boardArea: some View {
        switch model.snapshot?.board {
        case .available:
            // `model.tasks`, not the payload: the model promotes a task with something live here out of
            // the unstarted columns, and the board must render that promotion (ADR 0035).
            boardContent(model.tasks)
        case .unavailable(let reason):
            UnavailableView(reason: reason)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func boardContent(_ tasks: [DeskTask]) -> some View {
        if tasks.isEmpty {
            EmptyStateView(title: "No tasks yet", message: "Describe the first piece of work, or run Findings to learn the codebase.") {
                // The columns — and their add rows — are not drawn on an empty board, so the first task is typed here.
                HStack(spacing: 8) {
                    Button("New Task") { model.present(.addTask(BoardColumn.backlog.rawValue)) }
                        .buttonStyle(DeskButtonStyle(kind: .primary))
                        .disabled(model.snapshot?.repositoryRoot == nil)
                    Button("Open Findings") { model.go(.findings) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary))
                }
            }
        } else {
            let columns = visibleColumns.map { column in
                ColumnEntry(column: column,
                            tasks: BoardOrder.inColumn(column, tasks.filter { model.inWorkColumn($0, column) && matches($0) }))
            }
            if (!model.searchText.isEmpty || model.taskFilter.isActive) && columns.allSatisfy({ $0.tasks.isEmpty }) {
                Text(model.searchText.isEmpty ? "No tasks match these filters." : "No tasks match “\(model.searchText)”.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // The Focus layout (2026-09-20): Next up and Review keep a column's width, In progress takes
                // the rest, and Done is the strip at the edge. No column surface — the cards sit on the
                // board's own ground, so the eye lands on the outlined run and not on four boxes.
                GeometryReader { proxy in
                    // Wide enough for the Focus layout, or not: a flexible column between fixed ones starves
                    // silently when the room runs out, so the fallback is chosen here rather than discovered
                    // as a 48 pt In progress.
                    let fits = Self.fitsFocusLayout(width: proxy.size.width, columns: columns.count)
                    ScrollView(fits ? .vertical : [.vertical, .horizontal]) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(columns) { entry in
                                BoardColumnView(column: entry.column, tasks: entry.tasks, model: model,
                                                isCompact: !fits,
                                                collapseDone: entry.column == .done ? { hidesDone = true } : nil)
                            }
                            if hidesDone {
                                doneStrip(count: doneCount(tasks))
                            }
                        }
                        .padding(16)
                        .frame(minWidth: fits ? proxy.size.width : nil, alignment: .topLeading)
                        .pullToRefresh(isRefreshing: model.isRefreshing) { await model.sync() }
                    }
                    .pullToRefreshSpace()
                }
            }
        }
    }

    /// Room for every side column at its floor, the Done strip, the gaps and the padding, and still
    /// `focusMinWidth` left for In progress.
    static func fitsFocusLayout(width: CGFloat, columns: Int) -> Bool {
        let sides = CGFloat(max(columns - 1, 0)) * sideColumnMinWidth
        let chrome = 32 + CGFloat(columns) * 14 + doneStripWidth
        return width - sides - chrome >= focusMinWidth
    }

    private var visibleColumns: [BoardColumn] {
        // No Backlog column: Work's milestone list is the backlog; Queued rides in the first column (ADR 0046).
        ProjectWindowModel.workColumns.filter { !(hidesDone && $0 == .done) }
    }

    private func doneCount(_ tasks: [DeskTask]) -> Int {
        tasks.filter { model.inWorkColumn($0, .done) && matches($0) }.count
    }

    /// Done, closed: what merged, as a number you can open. It replaced a Hide Done switch above the board —
    /// a switch that had to be found to give the board its width back, and said nothing while it was off.
    private func doneStrip(count: Int) -> some View {
        Button { hidesDone = false } label: {
            VStack(spacing: 10) {
                Text("\(count)")
                    .font(DeskFont.mono(13, weight: .semibold))
                    .foregroundStyle(DeskColor.tone(.ended).foreground)
                Text(BoardColumn.done.title.uppercased())
                    .font(DeskFont.label)
                    .tracking(0.66)
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 56)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(width: Self.doneStripWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .deskCard(padding: 0)
        }
        .buttonStyle(.plain)
        .help("Show Done — \(count) merged")
        .accessibilityLabel("Show Done, \(count) merged")
    }

    private func matches(_ task: DeskTask) -> Bool {
        guard model.taskFilter.matches(task) else { return false }
        guard !model.searchText.isEmpty else { return true }
        let query = model.searchText.lowercased()
        if task.title.lowercased().contains(query) { return true }
        if task.issueLabel.lowercased().contains(query) { return true }
        if let meta = task.cardMeta, meta.lowercased().contains(query) { return true }
        return false
    }
}

private struct ColumnEntry: Identifiable {
    let column: BoardColumn
    let tasks: [DeskTask]
    var id: BoardColumn { column }
}

/// A column's title row: its name, what it holds, what is live in it, and the one control the column owns.
private struct BoardColumnHeader: View {
    let column: BoardColumn
    let model: ProjectWindowModel
    /// Set on Done only: the way back to the strip it came out of.
    var collapse: (() -> Void)?

    /// Over every card in the column, not the visible subset: a column filtered by the search box is still working.
    private var counts: (total: Int, live: Int) { model.workCounts(in: column) }

    /// What a column's header can do to the board: Backlog closes back to its rail, and In progress opens its
    /// running tasks side by side — offered only when there are two to watch, never greyed out in wait.
    @ViewBuilder private var columnControl: some View {
        if column == .inProgress, model.parallelTasks.count > 1 {
            Button { model.setMode(.parallel) } label: {
                Label("Side by side", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .help("Watch these \(model.parallelTasks.count) tasks run next to each other")
        }
        if let collapse {
            Button { collapse() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .buttonStyle(.plain)
            .help("Close Done back to its strip")
            .accessibilityLabel("Hide Done")
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: column.icon)
                .imageScale(.small)
                .foregroundStyle(DeskColor.mutedInk)
            SectionLabel(column == .readyForDev ? model.firstWorkColumnTitle : column.title)
            Text("\(counts.total)")
                .font(DeskFont.label)
                .tracking(0.66)
                .foregroundStyle(DeskColor.disabledDot)
            // The count of what is actually running here, so a column never looks idle while it works.
            if counts.live > 0 {
                HStack(spacing: 4) {
                    StatusDot(tone: .running, pulses: true, size: 6)
                    Text("\(counts.live) live")
                        .font(DeskFont.label)
                        .tracking(0.66)
                        .foregroundStyle(DeskColor.tone(.running).foreground)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(counts.live) running in \(column.title)")
            }
            Spacer(minLength: 0)
            columnControl
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BoardColumnView: View {
    let column: BoardColumn
    let tasks: [DeskTask]
    let model: ProjectWindowModel
    /// The board had no room for the Focus layout: every column is a column again and the board scrolls
    /// sideways, so In progress keeps the wide card but not the width.
    var isCompact = false
    /// Done's way back to the strip; nil on every other column.
    var collapseDone: (() -> Void)?
    /// In progress is where a run is watched, so it takes the wide card and the width (the Focus layout).
    private var isFocus: Bool { column == .inProgress }
    @State private var pending: PendingMove?
    /// Done keeps only the latest few (Settings › Work); the rest is a count, not a scroll.
    private var doneLimit: Int { model.snapshot?.workSettings.doneLimit ?? 10 }
    private var shownTasks: [DeskTask] {
        column == .done && doneLimit > 0 ? Array(tasks.prefix(doneLimit)) : tasks
    }
    private var hiddenCount: Int { tasks.count - shownTasks.count }

    /// A Start that would change a function a running task is changing waits here for the developer's answer.
    @State private var overlapAsk: (task: DeskTask, overlap: StartOverlap)?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @Environment(\.terminals) private var terminals
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @AppStorage(PreferenceKey.startWith) private var startWithData = Data()
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    /// Filing runs in the background, so it uses the Background runs setting rather than the default connection.
    private var backgroundConnection: String {
        BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
    }

    /// Stop what this card has live, or continue it. An issue card continues by running its door again; a
    /// branch card has no issue for `/dev` to open, so it continues in its own agent, where Start is one press.
    private func runControls(for task: DeskTask) -> CardRunControls? {
        guard task.column != .done, model.runHost(of: task) == nil else { return nil }
        let live = model.cardActivity(of: task) != nil
        let guests = model.runGuests(of: task)
        // Only the "no issue number" case belongs to the agent fallback: a sample project or an unverified
        // connection blocks the agent for the same reason, so offering it there just moves the refusal.
        let canStartDoor = task.taskNumber != nil && model.startBlockedReason(for: task, agent: defaultConnection) == nil
        return CardRunControls(
            isLive: live,
            stop: {
                // Whichever of the three is live — the precedence that decides the badge does not decide this.
                terminals?.end(taskID: task.id)
                terminals?.end(taskID: task.id)
                if let number = task.taskNumber { terminals?.end(taskID: DoorRuns.id(task: number)) }
                // Stopping the card stops the run working it, whichever card it was started from.
                for guest in guests {
                    terminals?.end(taskID: guest.id)
                    if let id = DoorRuns.id(for: guest) { terminals?.end(taskID: id) }
                }
            },
            resume: {
                if canStartDoor {
                    model.startTask(task, agent: defaultConnection)
                } else {
                    // Continue means continue: start the agent, then go to where it lives (ADR 0026).
                    // Opening a tab and leaving Start to be pressed was navigation wearing an action's label.
                    if case .ready(let kind) = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? [],
                                   terminalAgents: model.snapshot?.terminalAgents ?? []),
                       let started = terminals?.startAgent(for: task, agent: kind, worktreeLocation: worktreeLocation,
                                                           mode: RunModeChoice.current(for: model.ref)) {
                        // Starting the agent is starting the task, so the card leaves Ready for dev too
                        // (ADR 0035) — but only once the launch really ran, not for a skipped start.
                        Task { if case .launched = await started.value { await model.recordStarted(task) } }
                    }
                    model.selectedSessionID = task.id
                    model.go(.terminals)
                }
            },
            resumeTitle: canStartDoor ? "Continue — run /dev again" : "Continue in the agent")
    }

    /// A branch card's own menu. A card with an issue keeps the tracker moves instead, so neither card carries two.
    private func branchActions(for task: DeskTask) -> BranchActions? {
        guard task.issueNumber == nil, let branch = task.branch else { return nil }
        return BranchActions(
            openTerminal: { model.selectedSessionID = task.id; model.go(.terminals) },
            compare: { model.openTask(task.id); model.tab = .changes },
            copyName: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(branch, forType: .string)
            },
            // Only a plain local branch, and never the one checked out here: git refuses that, so offering it
            // could only ever produce "cannot delete branch … used by worktree at …".
            delete: task.isBranchCard && branch != model.snapshot?.project.branch
                ? { model.present(.deleteBranch(branch)) } : nil)
    }

    private func localActions(for task: DeskTask) -> LocalActions? {
        guard let item = model.localBacklogItem(for: task) else { return nil }
        let canPromote = model.localBacklogReason == nil && model.runBlockedReason(agent: backgroundConnection) == nil
        return LocalActions(
            fileOnGitHub: canPromote ? { model.promoteLocalItem(task, jobs: jobs, agent: backgroundConnection) } : nil,
            openFile: { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) },
            // Removal is confirmed in the dialog, where the entry's title is on screen to confirm against.
            remove: { model.openTask(task.id) })
    }

    /// The "Start with" list, for exactly the cards that offer Start: a card with nothing to start has nothing to
    /// hand another app either.
    private func startWithItems(for task: DeskTask) -> [StartWithItem]? {
        guard start(for: task) != nil else { return nil }
        return StartWithList.decode(startWithData).map { entry in
            StartWithItem(id: entry.id, name: entry.name, isAvailable: StartWithRows.isAvailable(entry),
                          start: { model.start(task, with: entry, agent: defaultConnection) })
        }
    }

    /// A card offers Start only when pressing it would actually run something; the dialog still explains why
    /// not. Backlog offers none: starting is what moves a card to In progress (ADR 0035), and the flow says
    /// a card reaches a run through Ready for dev.
    /// A card whose run is working another card's branch says so where its note goes; the run itself is on that card.
    private func noted(_ task: DeskTask) -> DeskTask {
        guard let host = model.runHost(of: task) else { return task }
        var task = task
        task.cardNote = "Running as \(host.issueLabel.isEmpty ? host.title : host.issueLabel) — its card shows the run"
        task.cardNoteIsWarning = false
        return task
    }

    /// The session "Show the run" opens: the card's own, or the live run of another card working this one's branch.
    private func runSessionID(for task: DeskTask) -> String {
        guard model.activity(of: task) == nil, let guest = model.runGuests(of: task).first else { return task.id }
        return [DoorRuns.id(for: guest), guest.id].compactMap { $0 }.first { model.sessions.state(for: $0).isLive } ?? guest.id
    }

    private func start(for task: DeskTask) -> (() -> Void)? {
        // A card whose run is working elsewhere is not idle, even though its own card shows nothing running.
        guard model.runHost(of: task) == nil else { return nil }
        guard column != .done, column != .backlog,
              model.startBlockedReason(for: task, agent: defaultConnection) == nil else { return nil }
        // The sheet on a task's FIRST start, and whenever ⌥ asks for it; after that the remembered launch
        // runs without a second dialog (ADR 0036 §10.3 answer 3). Auto never comes through here.
        return {
            if let same = model.startOverlaps(for: task).first(where: \.isSameCode) {
                overlapAsk = (task, same)
            } else {
                begin(task)
            }
        }
    }

    private static let overlapMessage = "Queue after waits until it is done, then this card can start. Start anyway runs both, and their branches will conflict at merge."

    private var overlapTitle: String {
        guard let ask = overlapAsk else { return "" }
        let file = (ask.overlap.file as NSString).lastPathComponent
        return "#\(ask.overlap.issue) is in progress and changes \(file) › \(ask.overlap.code ?? "")"
    }

    private var isAskingOverlap: Binding<Bool> {
        Binding(get: { overlapAsk != nil }, set: { if !$0 { overlapAsk = nil } })
    }

    @ViewBuilder private var overlapButtons: some View {
        if let ask = overlapAsk {
            Button("Queue after #\(ask.overlap.issue)") {
                overlapAsk = nil
                Task { await model.queueAfter(ask.task, blocker: ask.overlap.issue) }
            }
            Button("Start anyway") {
                overlapAsk = nil
                begin(ask.task)
            }
        }
        Button("Cancel", role: .cancel) { overlapAsk = nil }
    }

    /// "#814 also edits route.js" when a running task changes the same file but not the same function.
    private func sameFileNote(for task: DeskTask) -> String? {
        let files = model.startOverlaps(for: task).filter { !$0.isSameCode }
        guard !files.isEmpty else { return nil }
        return files.map { "#\($0.issue) also edits \(($0.file as NSString).lastPathComponent)" }.joined(separator: " · ")
            + " — different code, so git merges it cleanly."
    }

    private func begin(_ task: DeskTask) {
        if model.remembersLaunch(for: task), !NSEvent.modifierFlags.contains(.option) {
            model.startTask(task, agent: defaultConnection, using: model.rememberedLaunch(for: task))
        } else {
            model.present(.startTask(task.id))
        }
    }

    /// Every column that can take a typed task ends in the same row. The task is written to `docs/backlog/`
    /// (ADR 0027), so a sample project — no folder on disk to write into — keeps the button visible but
    /// disabled, with the reason on it.
    var body: some View {
        VStack(alignment: .leading, spacing: isFocus ? 10 : 8) {
            BoardColumnHeader(column: column, model: model, collapse: collapseDone)
            ForEach(shownTasks) { task in
                TaskCard(task: noted(task), isLastOpened: task.id == model.lastOpenedTaskID,
                         action: { model.openTask(task.id) }, moves: moves(for: task),
                         activity: model.cardActivity(of: task), isWaiting: model.isCardWaiting(task), start: start(for: task),
                         branchActions: branchActions(for: task),
                         localActions: localActions(for: task),
                         runControls: runControls(for: task),
                         startWith: startWithItems(for: task),
                         startNote: sameFileNote(for: task),
                         editStartWith: {
                             model.settingsSection = .startWith
                             model.present(.settings)
                         },
                         isCheckedOut: task.branch != nil && task.branch == model.snapshot?.project.branch,
                         variant: isFocus ? .focus : .column,
                         showRun: { model.selectedSessionID = runSessionID(for: task); model.go(.terminals) })
            }
            if shownTasks.isEmpty {
                Text(column == .inProgress ? "Nothing is running. Start a task from Next up."
                                           : "Nothing here.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .padding(.horizontal, 2)
            }
            if hiddenCount > 0 {
                Text("\(hiddenCount) more merged — Settings › Work sets how many Done shows")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(.horizontal, 2)
            }
        }
        // Next up and Review are a column wide and compress to their floor; In progress takes everything
        // they leave. On a board too narrow for that, every column is the full width and the board scrolls.
        .frame(minWidth: isFocus ? BoardScreen.focusMinWidth
                                 : (isCompact ? BoardScreen.sideColumnWidth : BoardScreen.sideColumnMinWidth),
               maxWidth: isFocus && !isCompact ? .infinity : BoardScreen.sideColumnWidth,
               alignment: .leading)
        .confirmationDialog(pending.map { TrackerWrite.confirmation(issue: $0.issue, slug: model.snapshot?.slug ?? "", action: $0.action) } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(pending?.confirmTitle ?? "Move") { commit() }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        // ADR 0046 decision 11: a running task already changes this function — merging both would conflict.
        .confirmationDialog(overlapTitle, isPresented: isAskingOverlap, titleVisibility: .visible) {
            overlapButtons
        } message: {
            Text(Self.overlapMessage)
        }
    }

    /// The column's one lifecycle move (ADR 0035). Branch, pull-request and merged cards are git's own and
    /// keep their menus unchanged; every card that can carry a stage — an issue's or a `docs/backlog/`
    /// entry's — offers the move its column allows. Done offers none: its revert flow is deferred.
    private func moves(for task: DeskTask) -> CardMoves? {
        guard !task.isBranchCard, !task.isMerged, !task.id.hasPrefix("pr:") else { return nil }
        let cancel: (() -> Void)? = task.issueNumber == nil ? nil : { model.present(.cancelTask(task.id)) }
        var moves: CardMoves
        switch task.column {
        case .backlog:
            moves = CardMoves(title: "Move to Next up", blockedReason: nil,
                              move: { Task { await model.moveToReadyForDev(task) } }, cancel: cancel)
        case .readyForDev:
            // Only a card moved here by hand has a stage to undo; one here by its milestone or as a P0 does not.
            let byHand = task.milestone != model.snapshot?.activeMilestone && task.priority != "P0"
            moves = CardMoves(title: byHand ? "Not now — back to Not started" : nil, blockedReason: nil,
                              move: { Task { await model.returnToBacklog(task) } }, cancel: cancel)
        case .queued, .inProgress:
            // In progress can refuse: git owns the column once commits exist, and the model says why.
            moves = CardMoves(title: "Cancel — back to Next up",
                              blockedReason: task.column == .inProgress ? model.stageBackBlockedReason(for: task) : nil,
                              move: { Task { await model.cancelToReadyForDev(task) } }, cancel: cancel)
        case .review where task.isFinishedReport:
            // Approval is the only way forward, and it is the dialog's button; there is no pull request to draft.
            return nil
        case .review:
            // Through the pull request, not around it: converting the PR to a draft is the fact that
            // moves the card, so it goes through the same confirmation as every tracker write.
            return CardMoves(title: "Back to In progress — convert the pull request to a draft",
                             blockedReason: task.pullRequestNumber == nil
                                 ? "No pull request number is known for this card, so there is nothing to convert." : nil,
                             move: { if let number = task.pullRequestNumber { pending = PendingMove(issue: number, action: .draftPullRequest) } },
                             cancel: cancel)
        case .done:
            return nil
        }
        // Between milestones, on GitHub, through the same confirmation as every tracker write.
        if let number = task.issueNumber, model.snapshot?.slug != nil {
            moves.milestones = model.openMilestones
            moves.currentMilestone = task.milestone
            moves.moveToMilestone = { title in pending = PendingMove(issue: number, action: .queue(milestone: title)) }
            if task.milestone != nil {
                moves.removeFromMilestone = { pending = PendingMove(issue: number, action: .backlog) }
            }
        }
        return moves
    }

    private func commit() {
        guard let move = pending else { return }
        pending = nil
        Task { await model.performTrackerWrite(issue: move.issue, action: move.action) }
    }
}

private struct PendingMove {
    let issue: Int
    let action: TrackerAction

    var confirmTitle: String {
        switch action {
        case .queue: return "Move"
        case .backlog: return "Remove from milestone"
        case .cancel: return "Close"
        case .complete: return "Mark as completed"
        case .draftPullRequest: return "Convert to draft"
        // The dialog saves its own edit without a confirmation, so no card ever holds one of these.
        case .edit: return "Save"
        }
    }
}

struct BoardScreen_Previews: PreviewProvider {
    static var previews: some View {
        BoardPreviewHost()
            .frame(width: 1204, height: 868)
    }

    private struct BoardPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            BoardScreen(model: model)
                .task {
                    await model.load()
                    model.go(.board)
                }
        }
    }
}
