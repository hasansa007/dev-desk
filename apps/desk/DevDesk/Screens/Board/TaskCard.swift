import DeskCore
import SwiftUI

/// One board card; reused wherever a task list needs the same summary (D:162–232).
struct TaskCard: View {
    let task: DeskTask
    let isLastOpened: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .opacity(task.isDimmed ? 0.72 : 1)
        .accessibilityLabel(accessibilityLabel)
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
            if let note = task.cardNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(task.cardNoteIsWarning ? DeskColor.tone(.failed).dot : DeskColor.mutedInk)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
