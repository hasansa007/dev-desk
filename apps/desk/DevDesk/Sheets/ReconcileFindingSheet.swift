import DeskCore
import SwiftUI

struct ReconcileFindingSheet: View {
    let title: String
    let reconcile: Reconciliation?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var selectedRelationship: String

    init(title: String, reconcile: Reconciliation?, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.title = title
        self.reconcile = reconcile
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _selectedRelationship = State(initialValue: reconcile?.relationships.first?.id ?? "")
    }

    var body: some View {
        SheetChrome(title: title, confirmTitle: "Queue proposed update",                     confirmDisabled: reconcile == nil, onCancel: onCancel, onConfirm: onConfirm) {
            if let reconcile {
                content(reconcile)
            } else {
                UnavailableView(reason: "Tracker updates are not available for this project.")
            }
        }
    }

    private func content(_ reconcile: Reconciliation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                card(reconcile.findingCard)
                card(reconcile.issueCard)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Relationship")
                VStack(spacing: 8) {
                    ForEach(reconcile.relationships) { option in
                        relationshipCard(option)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Proposed tracker update · review before sending")
                Text(reconcile.proposedUpdate.joined(separator: "\n"))
                    .font(DeskFont.mono(11.5))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(6)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
            }

            Text(reconcile.deliveryNote)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.tone(.failed).dot)
        }
    }

    private func card(_ compareCard: CompareCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(compareCard.title)
                .fontWeight(.semibold)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DeskColor.headerFill)
                .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) {
                Text(compareCard.body).lineSpacing(4)
                Text(compareCard.meta)
                    .font(compareCard.metaMonospaced ? DeskFont.mono(11.5) : DeskFont.secondary)
                    .foregroundStyle(DeskColor.secondaryInk)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    private func relationshipCard(_ option: RelationshipOption) -> some View {
        let isSelected = selectedRelationship == option.id
        return Button { selectedRelationship = option.id } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? DeskColor.accent : DeskColor.controlBorder)
                    .padding(.top, 2)
                (Text(option.title).fontWeight(.semibold) + Text(" — \(option.detail)"))
                    .foregroundStyle(DeskColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(isSelected ? DeskColor.accent : DeskColor.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct ReconcileFindingSheet_Previews: PreviewProvider {
    static var previews: some View {
        let finding = SampleData.studyHub().findings.value!.findings.first { $0.id == "F-108" }!
        ReconcileFindingSheet(title: "Compare finding F-108 with issue #42", reconcile: finding.reconcile, onCancel: {}, onConfirm: {})
            .frame(width: DeskMetric.dialogWidth)
    }
}
