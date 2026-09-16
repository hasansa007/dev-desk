import AppKit
import DeskCore
import SwiftUI

struct BoardScreen: View {
    @Bindable var model: ProjectWindowModel
    @State private var showsRules = false

    var body: some View {
        VStack(spacing: 0) {
            header
            boardArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
    }

    /// The title and the search, nothing else. Show backlog and Side by side sat up here as a switch styled as a
    /// button and a button disabled most of the time, both a screen's width from the columns they changed; each
    /// now lives on its column.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Board")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Spacer(minLength: 0)
            searchField
            if let note = model.snapshot?.boardNote, !note.isEmpty {
                rulesButton(note)
            }
        }
        .screenHeaderBar()
    }

    private var searchField: some View {
        TextField("Search tasks", text: $model.searchText)
            .textFieldStyle(.plain)
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.ink)
            .padding(.horizontal, 10)
            .frame(width: 200, alignment: .leading)
            .controlChrome()
    }

    /// The column rules are a paragraph; the header carries the control and shows the paragraph on demand.
    private func rulesButton(_ note: String) -> some View {
        Button { showsRules = true } label: {
            Image(systemName: "info.circle")
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("How these columns are decided")
        .accessibilityLabel("How these columns are decided")
        .popover(isPresented: $showsRules) {
            Text(note)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320)
                .padding(12)
        }
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
            EmptyStateView(title: "No tasks yet", message: "Describe the first piece of work, or run a survey to learn the codebase.") {
                Button("Open Survey") { model.go(.survey) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary))
            }
        } else {
            let columns = visibleColumns.map { column in
                ColumnEntry(column: column,
                            tasks: BoardOrder.inColumn(column, tasks.filter { $0.column == column && matches($0) }))
            }
            if !model.searchText.isEmpty && columns.allSatisfy({ $0.tasks.isEmpty }) {
                Text("No tasks match “\(model.searchText)”.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        HStack(alignment: .top, spacing: 14) {
                            if !model.showBacklog {
                                BacklogRail(count: model.counts(in: .backlog).total) { model.showBacklog = true }
                            }
                            ForEach(columns) { entry in
                                BoardColumnView(column: entry.column, tasks: entry.tasks, model: model)
                            }
                        }
                        .padding(16)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                        .pullToRefresh(isRefreshing: model.isRefreshing) { await model.load() }
                    }
                    .pullToRefreshSpace()
                }
            }
        }
    }

    private var visibleColumns: [BoardColumn] {
        BoardColumn.allCases.filter { $0 != .backlog || model.showBacklog }
    }

    private func matches(_ task: DeskTask) -> Bool {
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

/// The backlog, closed: always on the board, so the count is visible without a switch, and one click from open.
private struct BacklogRail: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
                Text("BACKLOG  \(count)")
                    .font(DeskFont.label)
                    .tracking(0.66)
                    .foregroundStyle(DeskColor.faintInk)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 18, height: 120)
            }
            .padding(.vertical, 12)
            .frame(width: 34, alignment: .top)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show the backlog")
        .accessibilityLabel("Backlog, \(count) tasks")
        .accessibilityHint("Shows the backlog column")
    }
}

private struct BoardColumnView: View {
    let column: BoardColumn
    let tasks: [DeskTask]
    let model: ProjectWindowModel
    @State private var pending: PendingMove?
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

    /// Over every card in the column, not the visible subset: a column filtered by the search box is still working.
    private var counts: (total: Int, live: Int) { model.counts(in: column) }

    /// Stop what this card has live, or continue it. An issue card continues by running its door again; a
    /// branch card has no issue for `/dev` to open, so it continues in its own agent, where Start is one press.
    private func runControls(for task: DeskTask) -> CardRunControls? {
        guard task.column != .done else { return nil }
        let live = model.activity(of: task) != nil
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
            resumeTitle: canStartDoor ? "Continue — run the door" : "Continue in the agent")
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
    private func start(for task: DeskTask) -> (() -> Void)? {
        guard column != .done, column != .backlog,
              model.startBlockedReason(for: task, agent: defaultConnection) == nil else { return nil }
        // The sheet on a task's FIRST start, and whenever ⌥ asks for it; after that the remembered launch
        // runs without a second dialog (ADR 0036 §10.3 answer 3). Auto never comes through here.
        return {
            if model.remembersLaunch(for: task), !NSEvent.modifierFlags.contains(.option) {
                model.startTask(task, agent: defaultConnection, using: model.rememberedLaunch(for: task))
            } else {
                model.present(.startTask(task.id))
            }
        }
    }

    /// Every column that can take a typed task ends in the same row. The task is written to `docs/backlog/`
    /// (ADR 0027), so a sample project — no folder on disk to write into — keeps the button visible but
    /// disabled, with the reason on it.
    private var addTaskButton: some View {
        let noFolder = model.snapshot?.repositoryRoot == nil
        return Button("+ Add a new task") { model.present(.addTask(column.rawValue)) }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            .disabled(noFolder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(noFolder
                  ? "This project has no folder on disk, so there is nowhere to write a task"
                  : "Type a task into \(column.title) — it is written to docs/backlog/")
    }

    /// What a column's header can do to the board: Backlog closes back to its rail, and In progress opens its
    /// running tasks side by side — offered only when there are two to watch, never greyed out in wait.
    @ViewBuilder private var columnControl: some View {
        if column == .backlog {
            Button { model.showBacklog = false } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide the backlog")
            .accessibilityLabel("Hide the backlog")
        } else if column == .inProgress, model.parallelTasks.count > 1 {
            Button { model.setMode(.parallel) } label: {
                Label("Side by side", systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .help("Watch these \(model.parallelTasks.count) tasks run next to each other")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: column.icon)
                    .imageScale(.small)
                    .foregroundStyle(DeskColor.mutedInk)
                SectionLabel(column.title)
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
            .frame(height: DeskMetric.columnHeaderHeight)
            ForEach(tasks) { task in
                TaskCard(task: task, isLastOpened: task.id == model.lastOpenedTaskID,
                         action: { model.openTask(task.id) }, moves: moves(for: task),
                         activity: model.activity(of: task), start: start(for: task),
                         branchActions: branchActions(for: task),
                         localActions: localActions(for: task),
                         runControls: runControls(for: task),
                         startWith: startWithItems(for: task),
                         editStartWith: {
                             model.settingsSection = .startWith
                             model.present(.settings)
                         },
                         isCheckedOut: task.branch != nil && task.branch == model.snapshot?.project.branch)
            }
            // Only where a new task could land: everything past Ready for dev is reached by moves and
            // starts, never by typing a card straight into it.
            if column == .backlog || column == .readyForDev {
                addTaskButton
            }
        }
        .padding(12)
        .frame(width: DeskMetric.boardColumnWidth, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
        .confirmationDialog(pending.map { TrackerWrite.confirmation(issue: $0.issue, slug: model.snapshot?.slug ?? "", action: $0.action) } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(pending?.confirmTitle ?? "Move") { commit() }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    /// The column's one lifecycle move (ADR 0035). Branch, pull-request and merged cards are git's own and
    /// keep their menus unchanged; every card that can carry a stage — an issue's or a `docs/backlog/`
    /// entry's — offers the move its column allows. Done offers none: its revert flow is deferred.
    private func moves(for task: DeskTask) -> CardMoves? {
        guard !task.isBranchCard, !task.isMerged, !task.id.hasPrefix("pr:") else { return nil }
        let cancel: (() -> Void)? = task.issueNumber == nil ? nil : { model.present(.cancelTask(task.id)) }
        switch task.column {
        case .backlog:
            return CardMoves(title: "Move to Ready for dev", blockedReason: nil,
                             move: { Task { await model.moveToReadyForDev(task) } }, cancel: cancel)
        case .readyForDev:
            return CardMoves(title: "Return to backlog", blockedReason: nil,
                             move: { Task { await model.returnToBacklog(task) } }, cancel: cancel)
        case .queued, .inProgress:
            // In progress can refuse: git owns the column once commits exist, and the model says why.
            return CardMoves(title: "Cancel — back to Ready for dev",
                             blockedReason: task.column == .inProgress ? model.stageBackBlockedReason(for: task) : nil,
                             move: { Task { await model.cancelToReadyForDev(task) } }, cancel: cancel)
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
        case .queue: return "Queue"
        case .backlog: return "Return to backlog"
        case .cancel: return "Close"
        case .complete: return "Mark as completed"
        case .draftPullRequest: return "Convert to draft"
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
