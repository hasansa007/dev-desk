import DeskCore
import SwiftUI

struct DecisionsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            SurfaceView(snapshot.decisions) { decisions in
                DecisionsSplitView(model: model, decisions: decisions)
            }
        }
    }
}

private struct DecisionsSplitView: View {
    @Bindable var model: ProjectWindowModel
    let decisions: [Decision]

    private var currentList: [Decision] {
        switch model.decisionsTab {
        case .needsAttention: return decisions.filter { $0.state == .needsAttention || $0.state == .stale }
        case .history: return decisions.filter { $0.state == .answered }
        }
    }

    private var selectedDecision: Decision? {
        if let id = model.selectedDecisionID, let match = currentList.first(where: { $0.id == id }) {
            return match
        }
        return currentList.first
    }

    private var emptyMessage: String {
        switch model.decisionsTab {
        case .needsAttention:
            var message = "Nothing needs your attention."
            if let snapshot = model.snapshot, !snapshot.isDemo {
                message += " Pending questions come from managed task sessions, which Dev Desk doesn't run yet."
            }
            return message
        case .history:
            return "No recorded decisions yet."
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let decision = selectedDecision {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    DecisionDetail(decision: decision, allDecisions: decisions, model: model)
                        .frame(maxWidth: 820, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
        } else {
            Text(emptyMessage)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(24)
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button("Needs attention") { model.decisionsTab = .needsAttention }
                    .buttonStyle(DeskButtonStyle(kind: model.decisionsTab == .needsAttention ? .primary : .secondary, size: .small))
                Button("History") { model.decisionsTab = .history }
                    .buttonStyle(DeskButtonStyle(kind: model.decisionsTab == .history ? .primary : .secondary, size: .small))
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            if currentList.isEmpty {
                Text(emptyMessage)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(currentList) { decision in
                            DecisionRow(decision: decision, isSelected: decision.id == selectedDecision?.id) {
                                model.selectedDecisionID = decision.id
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 288, alignment: .leading)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }
}

private struct DecisionRow: View {
    let decision: Decision
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(decision.listTitle)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                Text(decision.listMeta)
                    .font(DeskFont.small)
                    .foregroundStyle(decision.state == .stale ? DeskColor.tone(.waiting).foreground : DeskColor.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            .contentShape(Rectangle())
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected { Rectangle().fill(DeskColor.accent).frame(width: 3) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

struct DecisionsScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DecisionsPreviewHost(tab: .needsAttention)
                .frame(width: 1100, height: 780)
                .previewDisplayName("Needs attention")
            DecisionsPreviewHost(tab: .history)
                .frame(width: 1100, height: 780)
                .previewDisplayName("History")
        }
    }

    private struct DecisionsPreviewHost: View {
        let tab: DecisionsTab
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            DecisionsScreen(model: model)
                .task {
                    await model.load()
                    model.decisionsTab = tab
                }
        }
    }
}
