import DeskCore
import SwiftUI

/// The bounded moves a card offers, from `dev:kanban` Phase 7; nil for a card with no issue behind it.
struct CardMoves {
    /// The active milestone's title, or nil when the board could not read one.
    let milestone: String?
    let isQueued: Bool
    let queue: () -> Void
    let backlog: () -> Void
    let cancel: () -> Void
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

/// The Start control is an overlay, so the note sharing its band has to be told how much room it takes.
/// A constant would drift the moment the button's size token or its label changed, with nothing to catch it.
private struct StartWidthKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
    /// Stop and Continue, on every card that could be running something.
    var runControls: CardRunControls?
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
        if let branchActions {
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
                Button(moves.milestone.map { "Queue into \($0)" } ?? "Queue") { moves.queue() }
                    .disabled(moves.milestone == nil || moves.isQueued)
                Button("Return to backlog") { moves.backlog() }
                    .disabled(!moves.isQueued)
                Button("Cancel…") { moves.cancel() }
                Divider()
                Section("Git decides these") {
                    Button("In progress — cut a branch") {}.disabled(true)
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

    /// Stop what is live; continue what is not. Shown first, because it is the only entry about right now.
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
            if !metaText.isEmpty {
                Text(metaText)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
            }
            Text(branchFacts)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineLimit(1)
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
    private var ratingRow: some View {
        HStack(spacing: 6) {
            PropertyChip("impact \(task.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip("complexity \(task.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
        }
    }

    /// The branch's two facts on every card, dashed when this card has no branch — the same row either way.
    private var branchFacts: String {
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
