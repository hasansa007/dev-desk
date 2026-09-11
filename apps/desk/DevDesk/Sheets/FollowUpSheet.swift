import DeskCore
import SwiftUI

struct FollowUpSheet: View {
    let draft: FollowUpDraft
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var requestText: String

    init(draft: FollowUpDraft, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.draft = draft
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _requestText = State(initialValue: draft.request)
    }

    var body: some View {
        SheetChrome(title: "Request follow-up", confirmTitle: "Send request", width: 720,
                    onCancel: onCancel, onConfirm: onConfirm) {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.explanation)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DeskColor.neutralChipFill, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Reviewer note")
                    Text(draft.reviewerNote)
                        .lineSpacing(4)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Request")
                    TextEditor(text: $requestText)
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .scrollContentBackground(.hidden)
                        .frame(height: 90)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
                }

                HStack(spacing: 9) {
                    Text("Sent to").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                    PropertyChip(draft.recipient, tone: .info)
                }
            }
        }
    }
}

struct FollowUpSheet_Previews: PreviewProvider {
    static var previews: some View {
        let task = SampleData.studyHub().board.value!.first { $0.id == "42" }!
        FollowUpSheet(draft: task.followUp!, onCancel: {}, onConfirm: {})
            .frame(width: 720)
    }
}
