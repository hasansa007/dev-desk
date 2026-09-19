import DeskCore
import SwiftUI

/// The one lifecycle move a card's column offers (ADR 0035) — Backlog → Ready for dev → Queued →
/// In progress → Review, each column with its single forward or backward step — plus closing the issue.
/// Nil for the cards git owns (`branch:`, `pr:`, `merged:`) and for Done, whose revert flow is deferred.
struct CardMoves {
    /// What the move is called, e.g. "Move to Ready for dev".
    let title: String
    /// Why the move is disabled, shown as its help; nil when it can run.
    let blockedReason: String?
    let move: () -> Void
    /// Close the issue as not planned (the cancel sheet asks for the reason); nil with no issue behind the card.
    let cancel: (() -> Void)?
}

/// What a branch card can do. A card with no issue behind it had no menu at all, so nineteen of them could be
/// read and nothing else.
struct BranchActions {
    let openTerminal: () -> Void
    let compare: () -> Void
    let copyName: () -> Void
    /// nil when this card's branch is not this app's to delete — a pull request's head is not an abandoned branch.
    let delete: (() -> Void)?
}

/// What a `docs/backlog/` entry can do from its card (ADR 0027). It has no issue to move and no branch to
/// compare, so neither of the other two menus applies — and a card with no menu at all is a card that looks
/// broken beside the rest.
struct LocalActions {
    /// nil when there is no tracker to file into.
    let fileOnGitHub: (() -> Void)?
    let openFile: () -> Void
    let remove: () -> Void
}

/// The Start control is an overlay, so the note sharing its band has to be told how much room it takes.
/// A constant would drift the moment the button's size token or its label changed, with nothing to catch it.
private struct StartWidthKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One entry of the developer's "Start with" list, as a card's menu offers it.
struct StartWithItem: Identifiable {
    let id: String
    let name: String
    /// False for an app that is no longer where the list says; the menu keeps it, disabled, rather than hide it.
    let isAvailable: Bool
    let start: () -> Void
}

/// Stopping and continuing what a card is running. A card in In Progress is git's judgement about commits,
/// never a claim that anything is working — so the card says which, and offers the control that matches.
struct CardRunControls {
    let isLive: Bool
    let stop: () -> Void
    let resume: () -> Void
    let resumeTitle: String
}

/// One board card; reused wherever a task list needs the same summary (D:162–232).
struct TaskCard: View {
    let task: DeskTask
    let isLastOpened: Bool
    let action: () -> Void
    var moves: CardMoves?
    /// What this task has live in this window — a door run, its shell, or its agent. The app's own process
    /// state, never a claim about git's columns.
    var activity: TaskActivity?
    /// Starts the task from the card itself; nil when this card has nothing to start.
    var start: (() -> Void)?
    /// What a card with a branch but no issue can do; `moves` covers the ones with an issue.
    var branchActions: BranchActions?
    /// What a local backlog entry can do.
    var localActions: LocalActions?
    /// Stop and Continue, on every card that could be running something.
    var runControls: CardRunControls?
    /// The "Start with" list for a card that can start; nil hides the submenu, an empty list still offers editing it.
    var startWith: [StartWithItem]?
    var editStartWith: () -> Void = {}
    /// The branch this project has checked out. It is on the board like any other — a branch with unmerged
    /// commits is In Progress by git's rule (ADR 0011) — but git will not let it be deleted, so it says so
    /// rather than offering an action that can only fail.
    var isCheckedOut = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        // The card is NOT a Button. It was, with Start and the menu as overlays on top — and SwiftUI gives the
        // click to the outer button, so Start did nothing when pressed. Reported four times before it was
        // believed. A tap gesture on the card's own shape leaves its controls as ordinary children that work.
        content
            .opacity(task.isDimmed ? 0.72 : 1)
            .overlay(alignment: .topTrailing) { movesMenu.padding(7) }
            .overlay(alignment: .bottomTrailing) { startButton.padding(11) }
            .onPreferenceChange(StartWidthKey.self) { startWidth = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open") { action() }
    }

    @ViewBuilder private var movesMenu: some View {
        if let localActions {
            Menu {
                runEntries
                startWithEntries
                // A local card carries a stage like any issue card (ADR 0035): without this, a
                // docs/backlog/ entry could never reach Ready for dev.
                if let moves {
                    lifecycleEntry(moves)
                }
                if let file = localActions.fileOnGitHub {
                    Button("File on GitHub") { file() }
                }
                Button("Open the file") { localActions.openFile() }
                Divider()
                Button("Remove…", role: .destructive) { localActions.remove() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(task.title)")
        } else if let branchActions {
            Menu {
                runEntries
                Button("Open a terminal here") { branchActions.openTerminal() }
                Button("Compare with the base") { branchActions.compare() }
                Button("Copy branch name") { branchActions.copyName() }
                if let delete = branchActions.delete {
                    Divider()
                    Button("Delete branch…", role: .destructive) { delete() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(task.title)")
        } else if let moves {
            Menu {
                runEntries
                startWithEntries
                lifecycleEntry(moves)
                if let cancel = moves.cancel {
                    Button("Cancel…") { cancel() }
                }
                Divider()
                // Only the columns a move cannot reach: a start moves a card to In progress itself now
                // (ADR 0035), so that line is gone rather than contradicting the flow.
                Section("Git decides these") {
                    Button("Review — open a pull request") {}.disabled(true)
                    Button("Done — merge it") {}.disabled(true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Move \(task.issueLabel)")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Two lines whatever the title is. A three-line title made one card half again as tall as its
            // neighbour, which is what made a column read as a ragged list rather than a column.
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.tail)
                // The ⋮ is a top-trailing overlay and takes no layout space, so without this a long title
                // runs straight under it — worst on a branch name, which has no spaces to wrap at.
                .padding(.trailing, DeskMetric.cardMenuInset)
                .frame(maxWidth: .infinity, minHeight: DeskMetric.cardTitleHeight,
                       maxHeight: DeskMetric.cardTitleHeight, alignment: .topLeading)
            metaRow
                .padding(.top, 9)
            ratingRow
                .padding(.top, 7)
            stageRow
                .padding(.top, 7)
            // One band at the bottom, reserved on every card: the note reads along it, and the Start control
            // sits at its right as a sibling overlay — never a button inside a button. Two separate reserved
            // rows left every card without an action half-empty.
            bottomBand
                .padding(.top, 9)
        }
        .frame(height: DeskMetric.cardContentHeight, alignment: .topLeading)
        .deskCard(isSelected: isLastOpened)
    }

    /// Always present, so a card with something to say is not a different size from one without. The trailing
    /// inset keeps the note clear of the Start control sharing this band.
    private var bottomBand: some View {
        Text(task.cardNote ?? " ")
            .font(.system(size: 11))
            .foregroundStyle(task.cardNoteIsWarning ? DeskColor.tone(.failed).dot : DeskColor.mutedInk)
            .lineLimit(1)
            .padding(.trailing, offersStart ? startWidth + 8 : 0)
            .frame(maxWidth: .infinity, minHeight: DeskButtonStyle.Size.mini.height,
                   maxHeight: DeskButtonStyle.Size.mini.height, alignment: .leading)
    }

    /// The column's one move, disabled with its reason when it cannot honestly run — a card git holds
    /// In progress would not move, so the entry says so instead of doing nothing.
    private func lifecycleEntry(_ moves: CardMoves) -> some View {
        Button(moves.title) { moves.move() }
            .disabled(moves.blockedReason != nil)
            .help(moves.blockedReason ?? "")
    }

    /// Stop what is live; continue what is not. Shown first, because it is the only entry about right now.
    @ViewBuilder private var startWithEntries: some View {
        if let startWith {
            Menu("Start with") {
                ForEach(startWith) { item in
                    Button(item.name) { item.start() }
                        .disabled(!item.isAvailable)
                }
                if !startWith.isEmpty { Divider() }
                Button("Edit this list…") { editStartWith() }
            }
            Divider()
        }
    }

    @ViewBuilder private var runEntries: some View {
        if let runControls {
            if runControls.isLive {
                Button("Stop") { runControls.stop() }
            } else {
                Button(runControls.resumeTitle) { runControls.resume() }
            }
            Divider()
        }
    }

    /// Offered only when there is something to start and nothing already running for this task.
    private var offersStart: Bool { start != nil && activity == nil }

    @ViewBuilder private var startButton: some View {
        if let start, activity == nil {
            Button { start() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .accessibilityLabel("Start \(task.issueLabel.isEmpty ? task.title : task.issueLabel)")
            .background(GeometryReader { proxy in
                Color.clear.preference(key: StartWidthKey.self, value: proxy.size.width)
            })
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let activity {
                StatusPill(badge: StatusBadge(.running, activity.label, pulses: true))
            } else if isPaused {
                StatusPill(badge: StatusBadge(.waiting, "Paused"))
            }
            if isCheckedOut {
                StatusPill(badge: StatusBadge(.info, "Checked out"))
            }
            // Priority first, then the tags that change how a fix is reviewed (ADR 0046).
            if let priority = task.priority {
                PropertyChip(priority, tone: TaskFilterBar.tone(priority), verticalPadding: 0, horizontalPadding: 5)
            }
            ForEach(task.tags, id: \.self) { tag in
                PropertyChip(tag, verticalPadding: 0, horizontalPadding: 5)
            }
            if !metaText.isEmpty {
                Text(metaText)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
            }
            if !branchFacts.isEmpty {
                Text(branchFacts)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
            }
            if let badge = task.cardBadge {
                StatusPill(badge: badge)
            } else if let inline = task.cardInlineText {
                Text(inline)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
            }
        }
    }

    /// What the pipeline says this task has reached, from `.dev/<branch>.json` — the one thing the board knew
    /// and never showed. A bar rather than chips, because a card is 246 pt wide and seventeen phases are not.
    /// Advisory by `dev:kanban` 4.4: git decides the column, this only says how far along the branch claims to be.
    @ViewBuilder private var stageRow: some View {
        if let stages = task.pipeline?.stages, !stages.isEmpty {
            let done = stages.filter { $0.state == .done }.count
            let current = stages.first { $0.state == .current }?.name
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(current ?? (done == stages.count ? "Complete" : "Not started"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(done)/\(stages.count)")
                        .font(DeskFont.mono(10))
                        .foregroundStyle(DeskColor.faintInk)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DeskColor.controlBorder)
                        Capsule()
                            .fill(DeskColor.accent)
                            .frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(stages.count, 1)))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    /// On every card, so one card is not a different shape from the next: a dash where nothing rated it (ADR 0020).
    /// Chips are fixed-size, so "impact Medium · complexity Medium" was wider than the card and pushed it past
    /// its column. When the full row does not fit, the values shorten instead.
    @ViewBuilder private var ratingRow: some View {
        // Only what is set (ADR 0046, amending 0020): a row of dashes on most cards said nothing, every time.
        if task.impact != nil || task.complexity != nil {
        ViewThatFits(in: .horizontal) {
            ratingChips(impact: task.impact, complexity: task.complexity)
            ratingChips(impact: task.impact.map(Self.shortRating), complexity: task.complexity.map(Self.shortRating))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ratingChips(impact: String?, complexity: String?) -> some View {
        HStack(spacing: 6) {
            if let impact { PropertyChip("impact \(impact)", fill: DeskColor.neutralChipFill2, verticalPadding: 1) }
            if let complexity { PropertyChip("complexity \(complexity)", fill: DeskColor.neutralChipFill2, verticalPadding: 1) }
        }
    }

    private static func shortRating(_ value: String) -> String {
        value.caseInsensitiveCompare("Medium") == .orderedSame ? "Med" : value
    }

    /// The branch's two facts on every card, dashed when this card has no branch — the same row either way.
    private var branchFacts: String {
        // Nothing when there is no branch (ADR 0046): "— · —" on every unstarted card said nothing.
        guard task.lastCommit != nil || task.unmergedCount != nil else { return "" }
        let age = task.lastCommit.map { BranchAge.label($0) } ?? "—"
        let ahead = task.unmergedCount.map { "\($0) ahead" } ?? "—"
        return "\(age) · \(ahead)"
    }

    /// git puts a branch with unmerged commits In Progress (ADR 0011) and has no idea whether anyone is
    /// working. Nineteen cards saying In Progress while nothing ran is what that gap looks like; the column
    /// stays git's, and the card says what the app knows: nothing of this task is running.
    private var isPaused: Bool { task.column == .inProgress && activity == nil && runControls != nil }

    private var metaText: String {
        guard let meta = task.cardMeta else { return task.issueLabel }
        return task.issueLabel.isEmpty ? meta : "\(task.issueLabel) · \(meta)"
    }

    private var accessibilityLabel: String {
        // branchFacts is inside the button's label, which is a leaf to VoiceOver, so it is spoken only from here.
        [task.title, task.issueLabel, branchFacts, task.cardBadge?.label]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
