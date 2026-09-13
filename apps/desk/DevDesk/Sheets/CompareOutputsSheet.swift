import DeskCore
import SwiftUI

struct CompareOutputsSheet: View {
    let title: String
    let comparison: OutputComparison
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        SheetChrome(title: title, confirmTitle: comparison.confirmTitle,                     onCancel: onCancel, onConfirm: onConfirm) {
            VStack(alignment: .leading, spacing: 14) {
                Text(comparison.intro)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .frame(maxWidth: 840, alignment: .leading)

                HStack(alignment: .top, spacing: 14) {
                    card(comparison.left)
                    card(comparison.right)
                }

                Text(comparison.footnote)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
            }
        }
    }

    private func card(_ output: ComparedOutput) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(output.title).fontWeight(.semibold)
                Text(output.stateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(output.tone == .ended ? DeskColor.mutedInk : DeskColor.tone(output.tone).foreground)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeskColor.headerFill)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.border).frame(height: 1) }

            Text(output.summaryLines.joined(separator: "\n"))
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(5)
                .padding(12)

            Text(output.result)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }
}

struct CompareOutputsSheet_Previews: PreviewProvider {
    static var previews: some View {
        let task = SampleData.studyHub().board.value!.first { $0.id == "42" }!
        CompareOutputsSheet(title: "Compare agent outputs · #42", comparison: task.comparison!, onCancel: {}, onConfirm: {})
            .deskSheetWidth(DeskMetric.dialogWidth)
    }
}
