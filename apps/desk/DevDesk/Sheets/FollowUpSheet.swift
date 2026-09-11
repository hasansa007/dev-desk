import DeskCore
import SwiftUI

/// The request is shown read-only: the demo records that a follow-up was sent, never an edited text.
struct FollowUpSheet: View {
    let draft: FollowUpDraft
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        SheetChrome(title: "Request follow-up from the reviewer", confirmTitle: "Send request", width: 720,
                    onCancel: onCancel, onConfirm: onConfirm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(draft.explanation)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DeskColor.neutralChipFill, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Reviewer note")
                    box(draft.reviewerNote, color: DeskColor.ink)
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Request")
                    box(draft.request, color: DeskColor.secondaryInk)
                }
                .padding(.top, 14)

                HStack(spacing: 9) {
                    Text("Sent to").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                    PropertyChip(draft.recipient, tone: .info, verticalPadding: 2, horizontalPadding: 9)
                }
                .padding(.top, 12)
            }
        }
    }

    private func box(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .lineSpacing(4)
            .textSelection(.enabled)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }
}

struct FollowUpSheet_Previews: PreviewProvider {
    static var previews: some View {
        let task = SampleData.studyHub().board.value!.first { $0.id == "42" }!
        FollowUpSheet(draft: task.followUp!, onCancel: {}, onConfirm: {})
            .frame(width: 720)
    }
}
