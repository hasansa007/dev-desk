import DeskCore
import SwiftUI

struct EvidenceTab: View {
    let model: ProjectWindowModel
    let evidence: Surface<Evidence>

    var body: some View {
        SurfaceView(evidence) { evidence in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    SectionLabel("Checks")
                    if evidence.isDemo {
                        PropertyChip("Demo content")
                    }
                }
                if evidence.checks.isEmpty {
                    // The two sources: GitHub's checks for a pull request, and the run's own phase checkpoint.
                    Text("No checks yet. They appear once this task has a pull request, whose CI results are read here, "
                         + "or once its run checkpoints a phase.")
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.mutedInk)
                        .padding(.top, 8)
                } else {
                    checksTable(evidence.checks)
                        .padding(.top, 8)
                }
                if let failure = evidence.failure {
                    NoticeBanner(tone: .failed, title: failure.title, message: failure.message, style: .compact) {
                        HStack(spacing: 8) {
                            runnerButton("View log")
                            runnerButton("Retry run")
                        }
                    }
                    .padding(.top, 10)
                }
                if let limitations = evidence.limitations {
                    SectionLabel("Limitations")
                        .padding(.top, 18)
                    Text(limitations)
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .lineSpacing(5.3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if !evidence.linked.isEmpty {
                    SectionLabel("Linked evidence")
                        .padding(.top, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(evidence.linked.enumerated()), id: \.offset) { _, item in
                            TaskLinkedEvidenceRow(item: item) { model.openFinding($0) }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func checksTable(_ checks: [CheckResult]) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        return VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                if index > 0 {
                    Rectangle()
                        .fill(DeskColor.rowDivider)
                        .frame(height: 1)
                }
                TaskCheckRow(check: check)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius - 1))
        .padding(1)
        .background(DeskColor.surface, in: cardShape)
        .overlay(cardShape.strokeBorder(DeskColor.border))
    }

    private func runnerButton(_ title: String) -> some View {
        Button(title) {}
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            .fixedSize()
            .disabled(true)
            .help("No runner is connected, so there is no log or retry.")
    }
}

private struct TaskCheckRow: View {
    let check: CheckResult

    var body: some View {
        HStack(spacing: 0) {
            Text(check.name)
                .foregroundStyle(DeskColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(check.outcomeLabel)
                .foregroundStyle(outcomeColor)
            Text(check.revisionLabel)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
                .frame(width: 190, alignment: .trailing)
        }
        .font(DeskFont.body)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(check.outcome == .failed ? DeskColor.tone(.failed).fill : Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var outcomeColor: Color {
        switch check.outcome {
        case .passed: return DeskColor.tone(.running).foreground
        case .warning: return DeskColor.tone(.waiting).dot
        case .failed: return DeskColor.tone(.failed).dot
        }
    }
}

private struct TaskLinkedEvidenceRow: View {
    let item: LinkedEvidence
    let openFinding: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            PropertyChip(item.badge)
            if let findingID = item.findingID {
                Button("Open in Findings") { openFinding(findingID) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .fixedSize()
            }
        }
        .deskCard(padding: 10)
    }
}
