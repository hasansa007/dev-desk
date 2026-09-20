import DeskCore
import SwiftUI

/// What a finding is asking of you, in one word, and whether that question is already answered. The queue is
/// ordered by the report; this is what dims a row that has been decided and what its second line says.
struct FindingDecision {
    let label: String
    /// True once the finding has been filed, added to an issue, dropped or declined — nothing left to decide.
    let isSettled: Bool
    let tone: StatusTone
}

/// A finding in the queue on the left of the Findings screen. It was a wide table row with a checkbox, a kind,
/// an area, its sources and an action — a screen's width of columns repeated on every finding. The decision
/// moved to the focus pane beside it (2026-09-20), so the row is now only what picks the next one: is it
/// decided, what is it called, and what it is waiting for.
struct FindingRow: View {
    let finding: Finding
    let decision: FindingDecision
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                StatusDot(tone: decision.tone, size: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(DeskColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(finding.id) · \(decision.label)")
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 48, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.neutralChipFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .contentShape(Rectangle())
            // A decided finding stays in the queue, faded: it is what says how far through the run you are.
            .opacity(decision.isSettled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(finding.title)
        .accessibilityLabel("\(finding.id), \(finding.title), \(decision.label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Where a filed finding's card sits now. Read by `ResetFindingsSheet` too, so it stays here.
    static func tone(of column: BoardColumn) -> StatusTone {
        switch column {
        case .queued, .inProgress: return .running
        case .review: return .waiting
        case .done: return .ended
        case .backlog, .readyForDev: return .neutral
        }
    }
}
