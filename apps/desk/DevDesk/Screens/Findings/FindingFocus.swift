import DeskCore
import SwiftUI

/// One finding, in front of you, with its decision under it. The screen was a grid of cards, then a table of
/// rows with the filing button repeated on each — both asked you to compare findings you cannot act on at the
/// same time. A hunt produces a queue of yes/no questions, so the screen asks them one at a time (2026-09-20):
/// the queue on the left says where you are, this pane holds the only decision you are making.
struct FindingFocus: View {
    let finding: Finding
    @Bindable var model: ProjectWindowModel
    let decision: FindingDecision
    /// Which of the run's findings this is, for the "4 of 6" the queue's progress bar also shows.
    let position: (index: Int, total: Int)
    /// The next undecided finding, named on the footer so the queue reads as a queue.
    let next: Finding?
    let skip: () -> Void

    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    /// Filing runs in the background, so it uses the Background runs setting rather than the default connection.
    private var backgroundConnection: String {
        BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
    }

    /// The run this finding already started, when it has one: the decision is made, and this says how it is going.
    private var filing: BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    private var fileBlockedReason: String? {
        model.fileBlockedReason(key: finding.id, job: filing, agent: backgroundConnection)
    }

    private var isIgnored: Bool { model.ignoredFindings.contains(finding.id) }

    /// The width the eye reads a paragraph at; wider and the summary becomes a line you scan rather than read.
    private static let column: CGFloat = 700

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                identity
                Text(finding.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DeskColor.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !finding.summary.isEmpty {
                    MarkdownText(finding.summary, font: .system(size: 15), color: DeskColor.secondaryInk)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    verificationTile
                    sourcesTile
                }
                decisions
                footer
            }
            .frame(width: Self.column, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Text(finding.id)
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
            StatusPill(badge: StatusBadge(FindingTone.of(finding), finding.listDetail))
            PropertyChip(finding.kind.rawValue, fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            if isIgnored { StatusPill(badge: StatusBadge(.neutral, "Dropped")) }
            Spacer(minLength: 8)
            Text("\(position.index) of \(position.total)")
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
        }
    }

    private var verificationTile: some View {
        tile("Verification") {
            VStack(alignment: .leading, spacing: 6) {
                Text(finding.verificationLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                if !finding.limits.isEmpty {
                    MarkdownText(finding.limits, font: .system(size: 12), color: DeskColor.mutedInk)
                        .lineSpacing(3)
                }
            }
        }
    }

    private var sourcesTile: some View {
        tile("Sources · \(finding.locations.count)") {
            Text(finding.locations.isEmpty ? "No source locations recorded." : finding.locations.joined(separator: "\n"))
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 14)
    }

    // MARK: - The decision

    /// The three answers a finding can have, as three things to press rather than one button and a menu.
    /// While a filing run is going there is nothing to answer, so the row says what it is doing instead.
    @ViewBuilder private var decisions: some View {
        if let filing, filing.state.isLive {
            HStack(spacing: 10) {
                StatusPill(badge: StatusBadge(.running, "Filing…", pulses: true))
                Button("Show the run") { model.selectedSessionID = filing.id; model.go(.terminals) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                Button("Stop filing") { jobs?.stop(filing.id) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            }
        } else if let filed = finding.filing {
            HStack(spacing: 10) {
                StatusPill(badge: StatusBadge(.neutral, filed.label))
                if let task = model.boardTask(forFinding: finding.id) {
                    Button("Open its card — \(task.column.title)") { model.openTask(task.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                decisionButton("File it", "A new issue, with the report's evidence attached", isPrimary: true,
                               disabled: fileBlockedReason,
                               action: { model.fileToBacklog(finding.backlogDraft, jobs: jobs, agent: backgroundConnection) })
                if let issue = finding.reconcile?.candidateIssue {
                    decisionButton("Add to #\(issue)", "Compare it with the issue that may already cover it",
                                   action: { model.present(.reconcileFinding(finding.id)) })
                }
                if isIgnored {
                    decisionButton("Bring it back", "Put it back among the findings waiting on you",
                                   action: { model.restoreFinding(finding.id) })
                } else {
                    decisionButton("Drop it", "Ignored until you ask for ignored findings",
                                   action: { model.ignoreFinding(finding.id) })
                }
            }
        }
    }

    private func decisionButton(_ title: String, _ detail: String, isPrimary: Bool = false,
                                disabled: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isPrimary ? DeskColor.onColorInk : DeskColor.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(isPrimary ? DeskColor.onColorInk.opacity(0.85) : DeskColor.secondaryInk)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            // Filing is the accent, not green: green is running and amber is waiting, and neither is a button.
            .background(isPrimary ? DeskColor.accent : DeskColor.surface,
                        in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
                .strokeBorder(isPrimary ? DeskColor.accent : DeskColor.controlBorder))
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        }
        .buttonStyle(.plain)
        .disabled(disabled != nil)
        .opacity(disabled == nil ? 1 : 0.5)
        .help(disabled ?? model.backlogDestination)
    }

    /// Under the decision: leaving this one for later, the full finding, and what is next — so the pane says
    /// the queue keeps moving whichever button is pressed.
    private var footer: some View {
        HStack(spacing: 12) {
            Button(decision.isSettled ? "Next" : "Skip for now") { skip() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .disabled(next == nil)
            Button("Open full finding") { model.openFinding(finding.id) }
                .buttonStyle(LinkButtonStyle())
            Spacer(minLength: 8)
            Text(next.map { "decide each once · next: \($0.id)" } ?? "nothing left to decide")
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
        }
    }
}
