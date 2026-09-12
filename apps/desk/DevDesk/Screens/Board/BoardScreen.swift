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

    private var header: some View {
        HStack(spacing: 10) {
            Text("Board")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            searchField
            BacklogToggle(isOn: $model.showBacklog)
            if let note = model.snapshot?.boardNote, !note.isEmpty {
                rulesButton(note)
            }
            Spacer(minLength: 0)
            sideBySideButton
        }
        .screenHeaderBar()
    }

    /// The toolbar's old Focus/Parallel pair named two modes without naming what changed, and pressing either
    /// one usually changed nothing. This names the change, sits on the screen it changes, and says why it is
    /// unavailable instead of going quiet.
    @ViewBuilder private var sideBySideButton: some View {
        let running = model.parallelTasks
        Button(running.count > 1 ? "Side by side (\(running.count))" : "Side by side") {
            model.setMode(.parallel)
        }
        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
        .disabled(running.count < 2)
        .help(running.count < 2
              ? "Side by side needs two tasks in progress, each in its own checkout"
              : "Watch these \(running.count) tasks run next to each other")
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
        case .available(let tasks):
            boardContent(tasks)
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
                            ForEach(columns) { entry in
                                BoardColumnView(column: entry.column, tasks: entry.tasks, model: model)
                            }
                        }
                        .padding(16)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                    }
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

private struct BacklogToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text("Show backlog")
                .font(DeskFont.secondary)
                .foregroundStyle(isOn ? Color.white : DeskColor.ink)
                .padding(.horizontal, 10)
                .controlChrome(fill: isOn ? DeskColor.accent : DeskColor.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show backlog")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

private struct BoardColumnView: View {
    let column: BoardColumn
    let tasks: [DeskTask]
    let model: ProjectWindowModel
    @State private var pending: PendingMove?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @Environment(\.shellTerminals) private var terminals
    @Environment(\.agentTerminals) private var agents

    /// Over every card in the column, not the visible subset: a column filtered by the search box is still working.
    private var counts: (total: Int, live: Int) { model.counts(in: column) }

    /// Stop what this card has live, or continue it. An issue card continues by running its door again; a
    /// branch card has no issue for `/dev` to open, so it continues in its own agent, where Start is one press.
    private func runControls(for task: DeskTask) -> CardRunControls? {
        guard task.column != .done else { return nil }
        let live = model.activity(of: task) != nil
        let canStartDoor = model.startBlockedReason(for: task, agent: defaultConnection) == nil
        return CardRunControls(
            isLive: live,
            stop: {
                // Whichever of the three is live — the precedence that decides the badge does not decide this.
                agents?.end(taskID: task.id)
                terminals?.end(taskID: task.id)
                if let number = task.taskNumber { terminals?.end(taskID: DoorRuns.id(task: number)) }
            },
            resume: {
                if canStartDoor {
                    model.startTask(task, agent: defaultConnection)
                } else {
                    model.openTask(task.id)
                    model.tab = .agent
                }
            },
            resumeTitle: canStartDoor ? "Continue — run the door" : "Continue in the agent")
    }

    /// A branch card's own menu. A card with an issue keeps the tracker moves instead, so neither card carries two.
    private func branchActions(for task: DeskTask) -> BranchActions? {
        guard task.issueNumber == nil, let branch = task.branch else { return nil }
        return BranchActions(
            openTerminal: { model.openTask(task.id); model.tab = .shell },
            compare: { model.openTask(task.id); model.tab = .changes },
            copyName: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(branch, forType: .string)
            },
            // Only a plain local branch. An open pull request points at its head, so that branch is not abandoned.
            delete: task.isBranchCard ? { model.present(.deleteBranch(branch)) } : nil)
    }

    /// A card offers Start only when pressing it would actually run something; the dialog still explains why not.
    private func start(for task: DeskTask) -> (() -> Void)? {
        guard column != .done, model.startBlockedReason(for: task, agent: defaultConnection) == nil else { return nil }
        return { model.startTask(task, agent: defaultConnection) }
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
            }
            .frame(height: DeskMetric.columnHeaderHeight)
            ForEach(tasks) { task in
                TaskCard(task: task, isLastOpened: task.id == model.lastOpenedTaskID,
                         action: { model.openTask(task.id) }, moves: moves(for: task),
                         activity: model.activity(of: task), start: start(for: task),
                         branchActions: branchActions(for: task),
                         runControls: runControls(for: task))
            }
        }
        .frame(width: DeskMetric.boardColumnWidth, alignment: .leading)
        .confirmationDialog(pending.map { TrackerWrite.confirmation(issue: $0.issue, slug: model.snapshot?.slug ?? "", action: $0.action) } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(pending?.confirmTitle ?? "Move") { commit() }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    /// Only an issue can be moved: a branch or a pull request card has no issue to edit, and a merged card is history.
    private func moves(for task: DeskTask) -> CardMoves? {
        guard let issue = task.issueNumber, task.column != .done else { return nil }
        return CardMoves(
            milestone: model.activeMilestone,
            isQueued: task.column == .queued,
            queue: { pending = PendingMove(issue: issue, action: .queue(milestone: model.activeMilestone ?? "")) },
            backlog: { pending = PendingMove(issue: issue, action: .backlog) },
            cancel: { model.present(.cancelTask(task.id)) })
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
