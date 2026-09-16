import DeskCore
import SwiftUI

/// Cancelling asks for the reason first: a closed issue with no reason can't be told from one closed by accident,
/// and `dev:roadmap` reads these comments back so a declined direction is not re-proposed.
struct CancelTaskSheet: View {
    let model: ProjectWindowModel
    let task: DeskTask
    @State private var reason = ""

    private var trimmed: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SheetChrome(title: "Close \(task.issueLabel) as not planned", confirmTitle: "Close as not planned",
                    confirmDisabled: trimmed.isEmpty,
                    size: .confirm, onCancel: model.dismissSheet, onConfirm: confirm) {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                if let issue = task.issueNumber, let slug = model.snapshot?.slug {
                    Text(TrackerWrite.confirmation(issue: issue, slug: slug, action: .cancel(reason: trimmed)))
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.secondaryInk)
                }
                SectionLabel("Why").padding(.top, 4)
                TextField("It is superseded by #70", text: $reason, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .font(DeskFont.body)
                    .padding(8)
                    .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                Text("The reason is written as a comment on the issue. Reopening it is `gh issue reopen`.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
            }
        }
    }

    private func confirm() {
        guard let issue = task.issueNumber, !trimmed.isEmpty else { return }
        model.dismissSheet()
        Task { await model.performTrackerWrite(issue: issue, action: .cancel(reason: trimmed)) }
    }
}
