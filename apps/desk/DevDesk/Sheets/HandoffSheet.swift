import DeskCore
import SwiftUI

struct HandoffSheet: View {
    let title: String
    let plan: HandoffPlan
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var selectedProvider: String

    init(title: String, plan: HandoffPlan, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.plan = plan
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _selectedProvider = State(initialValue: plan.providers.first ?? "")
    }

    var body: some View {
        SheetChrome(title: title, confirmTitle: "Create new session",                     onCancel: onCancel, onConfirm: { onConfirm(selectedProvider) }) {
            VStack(alignment: .leading, spacing: 14) {
                MarkdownText(plan.warning, color: DeskColor.tone(.waiting).body)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DeskColor.tone(.waiting).fill, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.tone(.waiting).border))

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Handoff contents")
                    contentsBox
                }

                Text(plan.footnote)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
            }
        }
    }

    private var contentsBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(row.key).foregroundStyle(DeskColor.mutedInk).frame(width: 180, alignment: .leading)
                    Text(row.value)
                        .font(row.monospaced ? DeskFont.mono(12.5) : .system(size: 12.5, design: .monospaced))
                        .foregroundStyle(DeskColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
            }
            Rectangle().fill(DeskColor.rowDivider).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("New session with").foregroundStyle(DeskColor.mutedInk).frame(width: 180, alignment: .leading)
                Menu {
                    ForEach(plan.providers, id: \.self) { provider in
                        Button(provider) { selectedProvider = provider }
                    }
                } label: {
                    Text("\(selectedProvider) ▾").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(DeskColor.ink)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Text("· capabilities shown in Settings")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }
}

struct HandoffSheet_Previews: PreviewProvider {
    static var previews: some View {
        let task = SampleData.studyHub().board.value!.first { $0.id == "63" }!
        HandoffSheet(title: "Start with handoff · #63", plan: task.handoff!, onCancel: {}, onConfirm: { _ in })
            .deskSheetWidth(DeskMetric.dialogWidth)
    }
}
