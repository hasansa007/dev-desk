import DeskCore
import SwiftUI

struct DecisionDetail: View {
    let decision: Decision
    let allDecisions: [Decision]
    let model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch decision.state {
            case .needsAttention:
                NeedsAttentionBody(decision: decision, model: model)
                    .id(decision.id)
                staleFollowUps
            case .stale:
                staleBody
            case .answered:
                answeredBody
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(decision.question)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
            MarkdownText(decision.context, font: DeskFont.secondary, color: DeskColor.mutedInk)
        }
    }

    @ViewBuilder private var staleFollowUps: some View {
        let staleDecisions = allDecisions.filter { $0.state == .stale }
        ForEach(staleDecisions) { stale in
            VStack(alignment: .leading, spacing: 5) {
                Text("Stale decision · context changed")
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.tone(.waiting).foreground)
                Text(stale.staleReason ?? "")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(5)
                Button("Review this decision") { model.selectedDecisionID = stale.id }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
            .padding(.top, 20)
        }
    }

    private var staleBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            noticeBanner(for: decision.staleReason ?? "", tone: .waiting)
            if let answer = decision.answer {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Previous answer")
                    if let optionTitle = answer.optionTitle {
                        Text(optionTitle).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                    }
                    MarkdownText(answer.rationale, color: DeskColor.secondaryInk)
                }
            }
        }
    }

    private var answeredBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let answer = decision.answer {
                if let optionTitle = answer.optionTitle {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Answer")
                        Text(optionTitle).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Rationale")
                    MarkdownText(answer.rationale, color: DeskColor.secondaryInk)
                }
                Text(answer.answeredLabel)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            if let body = decision.body {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Record")
                    Text(body)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .deskCard(padding: 12)
                }
            }
        }
    }
}

/// Renders a single-string note as a bold lead sentence plus supporting detail.
private func noticeBanner(for text: String, tone: StatusTone) -> some View {
    let (title, message) = splitLeadSentence(text)
    return NoticeBanner(tone: tone, title: title, message: message)
}

private struct NeedsAttentionBody: View {
    let decision: Decision
    let model: ProjectWindowModel
    @State private var selectedOptionID: String?
    @State private var rationale = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice = decision.notice {
                noticeBanner(for: notice, tone: .waiting)
            }
            if let evidence = decision.evidence {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("Evidence considered")
                    MarkdownText(evidence, color: DeskColor.secondaryInk)
                        .lineSpacing(5)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(decision.options) { option in
                    OptionCard(option: option, isSelected: selectedOptionID == option.id) {
                        selectedOptionID = option.id
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Rationale")
                RationaleEditor(text: $rationale)
            }
            .frame(maxWidth: 820, alignment: .leading)

            HStack(spacing: 8) {
                Button(recordButtonTitle) {
                    model.recordAnswer(decisionID: decision.id, optionID: selectedOptionID, rationale: rationale)
                }
                .buttonStyle(DeskButtonStyle(kind: .primary))
                .disabled(selectedOptionID == nil)

                Button("Ask the agent for more evidence") {
                    model.requestMoreEvidence(decisionID: decision.id)
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary))
            }

            if model.answeredDecisionID == decision.id {
                noticeBanner(for: answeredMessage, tone: .running)
            }
        }
    }

    private var recordButtonTitle: String {
        guard let taskID = decision.taskID else { return "Record answer" }
        return "Record answer and resume #\(taskID)"
    }

    private var answeredMessage: String {
        guard let taskID = decision.taskID else {
            return "Answer recorded (demo). The answer appears in History with its rationale."
        }
        return "Answer recorded (demo). #\(taskID) moves from waiting to running and the answer appears in History with its rationale."
    }
}

private struct OptionCard: View {
    let option: DecisionOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                RadioDot(isSelected: isSelected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                    Text(option.detail).font(DeskFont.body).foregroundStyle(DeskColor.secondaryInk).lineSpacing(4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? DeskColor.tone(.info).fill : DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected ? DeskColor.accent : DeskColor.border))
        }
        .buttonStyle(.plain)
    }
}

private struct RadioDot: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .strokeBorder(isSelected ? DeskColor.accent : DeskColor.controlBorder, lineWidth: 1.5)
            .background { Circle().fill(DeskColor.accent).padding(3.5).opacity(isSelected ? 1 : 0) }
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }
}

private struct RationaleEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(DeskFont.body)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text("Explain the choice so a later review can judge it…")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.faintInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 60)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
        .accessibilityLabel("Rationale")
    }
}
