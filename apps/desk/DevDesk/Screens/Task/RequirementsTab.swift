import DeskCore
import SwiftUI

struct RequirementsTab: View {
    let requirements: Surface<Requirements>

    var body: some View {
        SurfaceView(requirements) { requirements in
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Goal")
                Text(requirements.goal)
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.ink)
                    .lineSpacing(4.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                if !requirements.criteria.isEmpty {
                    SectionLabel("Acceptance criteria")
                        .padding(.top, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(requirements.criteria.enumerated()), id: \.offset) { _, criterion in
                            TaskCriterionCard(criterion: criterion)
                        }
                    }
                    .padding(.top, 8)
                }
                if let outOfScope = requirements.outOfScope {
                    SectionLabel("Out of scope")
                        .padding(.top, 18)
                    Text(outOfScope)
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .lineSpacing(4.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let sources = requirements.sources {
                    SectionLabel("Sources")
                        .padding(.top, 18)
                    MarkdownText(sources, color: DeskColor.secondaryInk)
                        .lineSpacing(4.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let issueBody = requirements.body, !issueBody.isEmpty {
                    SectionLabel("Issue description")
                        .padding(.top, 18)
                    Text(issueBody)
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .deskCard(padding: 11)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

private struct TaskCriterionCard: View {
    let criterion: AcceptanceCriterion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: criterion.isMet ? "checkmark" : "circle")
                .imageScale(.small)
                .foregroundStyle(criterion.isMet ? DeskColor.tone(.running).dot : DeskColor.disabledDot)
                .accessibilityLabel(criterion.isMet ? "Met" : "Not met")
            Text(criterion.text)
                .foregroundStyle(DeskColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DeskFont.body)
        .deskCard(padding: 11)
        .accessibilityElement(children: .combine)
    }
}
