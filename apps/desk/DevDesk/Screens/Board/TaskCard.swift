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

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .opacity(task.isDimmed ? 0.72 : 1)
        .accessibilityLabel(accessibilityLabel)
        // A sibling overlay, not a child of the card's button, so opening the menu never also opens the task.
        .overlay(alignment: .topTrailing) { movesMenu.padding(7) }
    }

    @ViewBuilder private var movesMenu: some View {
        if let moves {
            Menu {
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
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            metaRow
                .padding(.top, 9)
            ratingRow
                .padding(.top, 7)
            if let note = task.cardNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(task.cardNoteIsWarning ? DeskColor.tone(.failed).dot : DeskColor.mutedInk)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The action the card is for, on the card. Reading a task should not be the price of starting one.
            if let start, activity == nil {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button { start() } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .accessibilityLabel("Start \(task.issueLabel.isEmpty ? task.title : task.issueLabel)")
                }
                .padding(.top, 9)
            }
        }
        .padding(11)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isLastOpened ? DeskColor.accent : DeskColor.border))
        .overlay {
            if isLastOpened {
                RoundedRectangle(cornerRadius: 9).inset(by: -1.5)
                    .stroke(DeskColor.accent.opacity(0.14), lineWidth: 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let activity {
                StatusPill(badge: StatusBadge(.running, activity.label, pulses: true))
            }
            if !metaText.isEmpty {
                Text(metaText)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
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

    /// Shown for anything still open with an issue behind it: a dash where the tracker has no rating, never a guess (ADR 0020).
    @ViewBuilder private var ratingRow: some View {
        if task.issueNumber != nil, task.column != .done {
            HStack(spacing: 6) {
                PropertyChip("impact \(task.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
                PropertyChip("complexity \(task.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            }
        }
    }

    private var metaText: String {
        guard let meta = task.cardMeta else { return task.issueLabel }
        return task.issueLabel.isEmpty ? meta : "\(task.issueLabel) · \(meta)"
    }

    private var accessibilityLabel: String {
        [task.title, task.issueLabel, task.cardBadge?.label]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
