import DeskCore
import SwiftUI

/// The one lifecycle move a card's column offers (ADR 0035) — Backlog → Ready for dev → Queued →
/// In progress → Review, each column with its single forward or backward step — plus closing the issue.
/// Nil for the cards git owns (`branch:`, `pr:`, `merged:`) and for Done, whose revert flow is deferred.
struct CardMoves {
    /// What the column move is called, e.g. "Move to Next up"; nil when the card has none to offer — a card in
    /// Next up because of its milestone is moved by moving the milestone, not by a stage (ADR 0046).
    let title: String?
    /// Why the move is disabled, shown as its help; nil when it can run.
    let blockedReason: String?
    let move: () -> Void
    /// Close the issue as not planned (the cancel sheet asks for the reason); nil with no issue behind the card.
    let cancel: (() -> Void)?
    /// Work's backlog is its milestone list, so "back to the backlog" became moving between milestones — a
    /// tracker write, confirmed like every other (ADR 0046).
    var milestones: [String] = []
    var currentMilestone: String? = nil
    var moveToMilestone: ((String) -> Void)? = nil
    var removeFromMilestone: (() -> Void)? = nil
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
    /// One card component, two shapes. Work's In progress column gets the board's width (the Focus layout,
    /// 2026-09-20), and a run that is being watched needs its stages, its last line and its answer button —
    /// none of which fit a 248 pt column. Everything else — the menus, Start, the accessibility label — is
    /// shared, so this is one card in two sizes rather than the per-column card ADR 0024 rejected.
    enum Variant { case column, focus }

    let task: DeskTask
    let isLastOpened: Bool
    let action: () -> Void
    var moves: CardMoves?
    /// What this task has live in this window — a door run, its shell, or its agent. The app's own process
    /// state, never a claim about git's columns.
    var activity: TaskActivity?
    /// The live session has ended its turn and is waiting for a message, which is not the same as working.
    var isWaiting = false
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
    /// Said on Start's hover when a running task edits the same file, different code (ADR 0046): a note, not a question.
    var startNote: String? = nil
    var editStartWith: () -> Void = {}
    /// The branch this project has checked out. It is on the board like any other — a branch with unmerged
    /// commits is In Progress by git's rule (ADR 0011) — but git will not let it be deleted, so it says so
    /// rather than offering an action that can only fail.
    var isCheckedOut = false
    /// Which shape this card takes; `.focus` is In progress, where the run is watched rather than listed.
    var variant: Variant = .column
    /// Where this task's run can be watched and answered. nil on a card with nothing live to open.
    var showRun: (() -> Void)?
    @State private var startWidth: CGFloat = 0

    var body: some View {
        // The card is NOT a Button. It was, with Start and the menu as overlays on top — and SwiftUI gives the
        // click to the outer button, so Start did nothing when pressed. Reported four times before it was
        // believed. A tap gesture on the card's own shape leaves its controls as ordinary children that work.
        card
            .opacity(task.isDimmed ? 0.72 : 1)
            .onPreferenceChange(StartWidthKey.self) { startWidth = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open") { action() }
    }

    /// The column card keeps its two overlays (the menu and Start float over a fixed-height block); the focus
    /// card lays both out in its own footer, because its height follows its content.
    @ViewBuilder private var card: some View {
        switch variant {
        case .column:
            content
                .overlay(alignment: .topTrailing) { movesMenu.padding(DeskMetric.cardPadding - 4) }
                .overlay(alignment: .bottomTrailing) { startButton.padding(DeskMetric.cardPadding) }
        case .focus:
            focusContent
        }
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
                .padding(.top, 10)
            ratingRow
                .padding(.top, 8)
            // One band at the bottom, reserved on every card: the note reads along it, and the Start control
            // sits at its right as a sibling overlay — never a button inside a button. Two separate reserved
            // rows left every card without an action half-empty.
            bottomBand
                .padding(.top, 9)
        }
        .frame(height: DeskMetric.cardContentHeight, alignment: .topLeading)
        .deskCard(padding: DeskMetric.cardPadding, isSelected: isLastOpened)
    }

    // MARK: - The focus card (In progress)

    /// In progress gets the board's width, so its card says what a run needs said: what it is, how far the
    /// pipeline got, its last line, and the one control — Answer, Show the run, or Start. The run that is
    /// waiting on you is the only outlined card on the board.
    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = focusBadge {
                    StatusPill(badge: badge)
                }
            }
            stageChips
            // The run's own last line, never truncated to one: on this card it is the sentence you read.
            if let note = task.cardNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(task.cardNoteIsWarning ? DeskColor.tone(.failed).dot : DeskColor.secondaryInk)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            focusFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: DeskMetric.cardPadding, border: focusBorder, isSelected: isLastOpened)
    }

    /// Amber when it is waiting on you, green while it runs — the two reserved colours, on the one card they
    /// are about. Every other card on the board keeps the hairline.
    private var focusBorder: Color {
        if isWaiting, activity != nil { return DeskColor.tone(.waiting).dot }
        if activity != nil { return DeskColor.tone(.running).border }
        return DeskColor.border
    }

    private var focusBadge: StatusBadge? {
        if let activity {
            return isWaiting ? StatusBadge(.waiting, "Needs a decision", symbol: "questionmark.diamond")
                             : StatusBadge(.running, activity.label, pulses: true)
        }
        if isPaused { return StatusBadge(.waiting, "Paused") }
        return task.cardBadge
    }

    /// The pipeline as the run's four steps, so how far it got is read at a glance rather than as "2/4".
    /// The current step is the accent, not green: green says running, and a step is a place, not a state.
    @ViewBuilder private var stageChips: some View {
        if let stages = task.pipeline?.stages, !stages.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(stages, id: \.name) { stage in
                    Text(stage.name)
                        .font(DeskFont.mono(11))
                        .foregroundStyle(stageInk(stage.state))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 9)
                        .background(stageFill(stage.state), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private func stageInk(_ state: StageState) -> Color {
        switch state {
        case .done: return DeskColor.secondaryInk
        case .current: return DeskColor.tone(.info).foreground
        case .pending: return DeskColor.faintInk
        }
    }

    private func stageFill(_ state: StageState) -> Color {
        switch state {
        case .done: return DeskColor.neutralChipFill
        case .current: return DeskColor.tone(.info).fill
        case .pending: return DeskColor.neutralChipFill2
        }
    }

    /// The facts on one line and the one control at its end — the focus card's Start, Answer or Show the run.
    private var focusFooter: some View {
        HStack(spacing: 8) {
            if let priority = task.priority {
                PropertyChip(priority, tone: TaskCard.priorityTone(priority), verticalPadding: 0, horizontalPadding: 5)
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
            Spacer(minLength: 8)
            focusAction
            movesMenu
        }
    }

    @ViewBuilder private var focusAction: some View {
        if let showRun, activity != nil {
            Button(isWaiting ? "Answer" : "Show the run") { showRun() }
                .buttonStyle(DeskButtonStyle(kind: isWaiting ? .primary : .secondary, size: .small))
                .help(isWaiting ? "The run stopped to ask something — answer it where it is waiting"
                                : "Watch this run where it is")
        } else {
            startButton
        }
    }

    /// Always present, so a card with something to say is not a different size from one without. The trailing
    /// inset keeps the note clear of the Start control sharing this band.
    /// A card with pipeline progress carries its bar here, under the note, rather than in a row of its own: the card is
    /// a fixed height, and the extra row pushed the note out of it and put Start over the bar.
    private var bottomBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(task.cardNote ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(task.cardNoteIsWarning ? DeskColor.tone(.failed).dot : DeskColor.mutedInk)
                    .lineLimit(1)
                    // One line beside Start cuts most notes short; the whole sentence is a hover away.
                    .help(task.cardNote ?? "")
                if let stages = task.pipeline?.stages, !stages.isEmpty {
                    Spacer(minLength: 4)
                    Text("\(stages.filter { $0.state == .done }.count)/\(stages.count)")
                        .font(DeskFont.mono(10))
                        .foregroundStyle(DeskColor.faintInk)
                }
            }
            if let stages = task.pipeline?.stages, !stages.isEmpty {
                progressBar(done: stages.filter { $0.state == .done }.count, of: stages.count)
            }
        }
            .padding(.trailing, offersStart ? startWidth + 8 : 0)
            .frame(maxWidth: .infinity, minHeight: DeskButtonStyle.Size.mini.height,
                   maxHeight: DeskButtonStyle.Size.mini.height, alignment: .leading)
    }

    /// The column's one move, disabled with its reason when it cannot honestly run — a card git holds
    /// In progress would not move, so the entry says so instead of doing nothing.
    @ViewBuilder private func lifecycleEntry(_ moves: CardMoves) -> some View {
        if let title = moves.title {
            Button(title) { moves.move() }
                .disabled(moves.blockedReason != nil)
                .help(moves.blockedReason ?? "")
        }
        if let moveTo = moves.moveToMilestone {
            let others = moves.milestones.filter { $0 != moves.currentMilestone }
            if !others.isEmpty {
                Menu("Move to milestone") {
                    ForEach(others, id: \.self) { title in Button(title) { moveTo(title) } }
                }
            }
        }
        if let remove = moves.removeFromMilestone {
            Button("Remove from milestone") { remove() }
        }
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
                // A paused card has been started; pressing it again picks the run back up.
                Label(isPaused ? "Continue" : "Start", systemImage: "play.fill")
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .help(startNote ?? "Start this task in its own worktree")
            .accessibilityLabel("\(isPaused ? "Continue" : "Start") \(task.issueLabel.isEmpty ? task.title : task.issueLabel)")
            .background(GeometryReader { proxy in
                Color.clear.preference(key: StartWidthKey.self, value: proxy.size.width)
            })
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let activity {
                StatusPill(badge: isWaiting ? StatusBadge(.waiting, "Waiting for you", symbol: "questionmark.diamond")
                                            : StatusBadge(.running, activity.label, pulses: true))
            } else if isPaused {
                StatusPill(badge: StatusBadge(.waiting, "Paused"))
            }
            if isCheckedOut {
                StatusPill(badge: StatusBadge(.info, "Checked out"))
            }
            // Priority first, then the tags that change how a fix is reviewed (ADR 0046).
            if let priority = task.priority {
                PropertyChip(priority, tone: TaskCard.priorityTone(priority), verticalPadding: 0, horizontalPadding: 5)
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

    private func progressBar(done: Int, of total: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DeskColor.controlBorder)
                Capsule().fill(DeskColor.accent).frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(total, 1)))
            }
        }
        .frame(height: 3)
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

extension TaskCard {
    /// Priority is the one strong colour on a card: P0 red, P1 amber, P2 blue, P3 grey.
    static func priorityTone(_ priority: String) -> StatusTone {
        switch priority {
        case "P0": return .failed
        case "P1": return .waiting
        case "P2": return .info
        default: return .neutral
        }
    }
}
