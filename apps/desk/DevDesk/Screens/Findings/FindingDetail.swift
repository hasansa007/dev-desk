import DeskCore
import SwiftUI

struct FindingDetail: View {
    let finding: Finding
    let model: ProjectWindowModel
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: 14) {
                sourceLocationsCard
                verificationLimitsCard
            }
            .padding(.top, 16)
            if let reconcile = finding.reconcile {
                ReconcileCard(finding: finding, reconcile: reconcile, model: model)
                    .padding(.top, 16)
            }
            if let historyNote = finding.historyNote {
                Text(historyNote)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.top, 14)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(finding.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                MarkdownText(finding.summary, color: DeskColor.secondaryInk)
                    .lineSpacing(5)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                PropertyChip(finding.verificationLabel, verticalPadding: 2, horizontalPadding: 9)
                HStack(spacing: 8) {
                    if model.ignoredFindings.contains(finding.id) {
                        Button("Stop ignoring") { model.restoreFinding(finding.id) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    } else {
                        Button("Ignore") { model.ignoreFinding(finding.id) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                            .help("Keeps this out of the list until you ask for ignored findings")
                    }
                    Button("Add to backlog…") { file() }
                        .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                        .disabled(model.runBlockedReason(agent: defaultConnection) != nil)
                        .help(model.runBlockedReason(agent: defaultConnection)
                              ?? "Queues dev:create-issue for this finding; it drafts and files with this repository's labels")
                }
            }
        }
    }

    private func file() {
        model.fileFromReport(jobs: jobs, itemID: finding.id, description: finding.backlogDescription,
                             agent: defaultConnection)
    }

    private var sourceLocationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Source locations")
            if finding.locations.isEmpty {
                Text("No source locations recorded.")
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.secondaryInk)
            } else {
                Text(finding.locations.joined(separator: "\n"))
                    .font(DeskFont.mono(11.5))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }

    private var verificationLimitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Verification limits")
            MarkdownText(finding.limits, font: .system(size: 12.5), color: DeskColor.secondaryInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }
}

private struct ReconcileCard: View {
    let finding: Finding
    let reconcile: Reconciliation
    let model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Reconcile with existing work").font(DeskFont.body.weight(.semibold))
                Text(reconcile.statusNote).font(DeskFont.small).foregroundStyle(DeskColor.mutedInk)
                Spacer(minLength: 8)
                Button("Compare with #\(reconcile.candidateIssue)…") {
                    model.present(.reconcileFinding(finding.id))
                }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .sheetHeader))
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            .background(DeskColor.headerFill)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(reconcile.guidance, id: \.self) { line in
                    Text("· \(line)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DeskColor.secondaryInk)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))

            if let queuedNote = reconcile.queuedNote {
                NoticeBanner(tone: .running, title: "", message: queuedNote, style: .compact)
                    .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14))
            }
        }
        .background(DeskColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DeskColor.border))
    }
}
