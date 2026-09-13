import DeskCore
import SwiftUI

/// A finding's card, opened — the same dialog a task card opens, assembled from the same chrome
/// (`DialogChrome.swift`). A finding and a task are both "one thing you might do something about", and reading
/// one in a split pane while the other got a dialog made the survey feel like a different app.
struct FindingDialog: View {
    let finding: Finding
    @Bindable var model: ProjectWindowModel
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var tab = Tab.overview

    private enum Tab: String, CaseIterable {
        case overview = "Overview", evidence = "Evidence", limits = "Verification"
    }

    private var isIgnored: Bool { model.ignoredFindings.contains(finding.id) }

    /// The run this finding already has, if any — the dialog's primary action has to know, or it offers to
    /// file a finding that is being filed.
    private var filing: BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    private var fileBlockedReason: String? {
        if let filing, filing.state.isLive { return "A run is already filing this one." }
        if let filing, case .asking = filing.state { return "That run is waiting for an answer." }
        if let filing, case .ended(_, let failed) = filing.state, !failed { return "This one has been filed." }
        return model.trackerBlockedReason ?? model.runBlockedReason(agent: defaultConnection)
    }

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: finding.title, identifier: finding.id, badges: badges, editURL: issueURL,
                         editHelp: "Open the issue it may already be tracked by", close: model.dismissSheet)
            DialogTabBar(titles: Tab.allCases.map(\.rawValue), selected: tab.rawValue) { title in
                if let next = Tab(rawValue: title) { tab = next }
            }
            DialogBody { meta } content: { content }
            footer
        }
        .deskDialogFrame()
    }

    private var badges: [StatusBadge] {
        var badges = [StatusBadge(FindingTone.of(finding), finding.listDetail)]
        if isIgnored { badges.append(StatusBadge(.neutral, "Ignored")) }
        return badges
    }

    /// A finding is not on GitHub. The pencil goes to the issue this may already be tracked by, when the
    /// report found one — and is absent otherwise rather than opening nothing.
    private var issueURL: URL? {
        guard let number = finding.reconcile?.candidateIssue, let slug = model.snapshot?.slug else { return nil }
        return URL(string: "https://github.com/\(slug)/issues/\(number)")
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let area = finding.area {
                PropertyChip(area.rawValue, fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            }
            PropertyChip("impact \(trackedTask?.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip("complexity \(trackedTask?.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip(finding.verificationLabel, fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip(finding.locations.isEmpty ? "no source locations" : "\(finding.locations.count) source\(finding.locations.count == 1 ? "" : "s")",
                         fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            Spacer(minLength: 8)
            Text("run \(finding.runID)")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .overview: overview
        case .evidence: evidence
        case .limits: limitsTab
        }
    }

    /// A rating comes from the tracker, so it exists only once this has been filed as an issue.
    private var trackedTask: DeskTask? {
        guard let number = finding.reconcile?.candidateIssue else { return nil }
        return model.tasks.first { $0.issueNumber == number }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            // What the category is asking of you, and where to answer it. "Needs a decision" named a decision
            // without ever saying what it was — the question was in the skill, not on screen.
            if let decision = finding.categories.compactMap(\.decision).first {
                NoticeBanner(tone: .waiting, title: decision.title, message: decision.message, style: .compact)
            }
            MarkdownText(finding.summary, color: DeskColor.secondaryInk)
                .lineSpacing(5)
                .frame(maxWidth: 760, alignment: .leading)
            if let reconcile = finding.reconcile {
                ReconcileCard(finding: finding, reconcile: reconcile, model: model)
            }
            if let historyNote = finding.historyNote {
                Text(historyNote)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
                    .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var evidence: some View {
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
    }

    private var limitsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("How far this was verified")
            Text(finding.verificationLabel)
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.ink)
            MarkdownText(finding.limits, font: .system(size: 12.5), color: DeskColor.secondaryInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        DialogFooter(primary: primaryAction,
                     secondary: DialogAction(title: isIgnored ? "Stop ignoring" : "Ignore",
                                             help: isIgnored ? "Puts it back in the list"
                                                             : "Keeps this out of the list until you ask for ignored findings",
                                             run: setAside),
                     close: model.dismissSheet)
    }

    /// Filing, unless this finding already has a run — then the action is to go and look at it.
    private var primaryAction: DialogAction {
        if let filing, filing.state.isLive || isAsking(filing) {
            return DialogAction(title: isAsking(filing) ? "Answer the run…" : "Show the run",
                                help: "Its log and its question are in Terminals") {
                model.dismissSheet()
                model.selectedSessionID = filing.id
                model.go(.terminals)
            }
        }
        if let filing, case .ended(_, true) = filing.state {
            return DialogAction(title: "Try filing again", help: "The last run ended with an error", run: file)
        }
        return DialogAction(title: "Add to backlog…", blockedReason: fileBlockedReason,
                            help: "Queues dev:create-issue for this finding; it drafts and files with this repository's labels",
                            run: file)
    }

    private func isAsking(_ job: BackgroundJob) -> Bool {
        if case .asking = job.state { return true }
        return false
    }

    private func file() {
        model.fileFromReport(jobs: jobs, itemID: finding.id, description: finding.backlogDescription,
                             agent: defaultConnection)
        model.dismissSheet()
    }

    private func setAside() {
        if isIgnored {
            model.restoreFinding(finding.id)
        } else {
            model.ignoreFinding(finding.id)
            model.dismissSheet()
        }
    }
}

/// The report found an issue this may already be. Comparing them is a decision, so it opens its own sheet.
struct ReconcileCard: View {
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

/// What colour a finding's category reads in. Confirmed work is information, an unconfirmed observation is a
/// question waiting on someone — neither is a failure, so neither is red.
enum FindingTone {
    static func of(_ finding: Finding) -> StatusTone {
        if finding.categories.contains(.new) { return .info }
        if finding.categories.contains(.needsDecision) { return .waiting }
        return .neutral
    }
}
