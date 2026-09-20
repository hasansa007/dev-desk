import DeskCore
import SwiftUI

struct FindingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            if case .available(let report) = snapshot.findings, !report.runs.isEmpty {
                FindingsFocus(model: model, report: report)
            } else {
                // The same header before the first hunt, or when the report cannot be read (ADR 0046 decision 14).
                VStack(spacing: 0) {
                    ScreenHeader(.findings) { EmptyView() } tools: { RunFindingsButton(model: model, size: .small) }
                    SurfaceView(snapshot.findings, fillsScreen: true) { _ in
                        EmptyStateView(title: "No hunt yet",
                                       message: "Hunt for issues to see what's wrong in this codebase: agents read each flow, and every finding is checked twice before it reaches you. The report lands in `docs/findings/`.") {
                            RunFindingsButton(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(DeskColor.canvas)
            }
        }
    }
}

/// Starts `dev:findings` as a run; the run's own pane asks for consent before anything executes. The action is
/// named for what it does — a hunt — while the screen keeps the name of what it holds (ADR 0046).
private struct RunFindingsButton: View {
    let model: ProjectWindowModel
    var size: DeskButtonStyle.Size = .regular

    var body: some View {
        DoorRunControl(model: model, door: "findings", title: "Hunt for issues", size: size)
    }
}

/// Findings, decided one at a time. It was a triage list of rows — and before that a grid of cards — where
/// every finding carried its own File button and the screen asked you to weigh sixteen at once. A hunt is a
/// queue of yes/no questions, so the screen is a queue and one question (2026-09-20): the list on the left
/// says how far through the run you are, the pane on the right holds the finding you are deciding.
private struct FindingsFocus: View {
    @Bindable var model: ProjectWindowModel
    let report: FindingsReport

    @State private var showsNote = false
    @State private var selectedID: String?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    /// Filing runs in the background, so it uses the Background runs setting rather than the default connection.
    private var backgroundConnection: String {
        BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
    }
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    /// The queue: wide enough for a finding's title, narrow enough that the decision keeps the screen.
    private static let queueWidth: CGFloat = 320

    private var runFindings: [Finding] {
        report.findings.filter { model.selectedRunID == nil || $0.runID == model.selectedRunID }
    }

    private var ignoredCount: Int { runFindings.filter { model.ignoredFindings.contains($0.id) }.count }

    /// Ignored findings stay in the queue, faded, until the Ignored chip makes them the queue: a decision you
    /// made is how you know you made it. The kind chips still narrow the list.
    private var visibleFindings: [Finding] {
        runFindings
            .filter { !model.showsIgnoredFindings || model.ignoredFindings.contains($0.id) }
            .filter { model.findingKindFilter == nil || $0.kind == model.findingKindFilter }
    }

    private var undecided: [Finding] { visibleFindings.filter { !decision(for: $0).isSettled } }

    private var selected: Finding? {
        visibleFindings.first { $0.id == selectedID } ?? undecided.first ?? visibleFindings.first
    }

    /// The one after the one on screen that still needs an answer — never the same one again.
    private var next: Finding? {
        guard let selected else { return undecided.first }
        let rest = visibleFindings.drop { $0.id != selected.id }.dropFirst()
        return rest.first { !decision(for: $0).isSettled } ?? undecided.first { $0.id != selected.id }
    }

    private var decidedCount: Int { visibleFindings.count - undecided.count }

    private var summary: String {
        let held = runFindings.filter { $0.categories.contains(.needsDecision) }.count
        let total = runFindings.count
        return "\(total) finding\(total == 1 ? "" : "s") · \(held) held"
            + (ignoredCount > 0 ? " · \(ignoredCount) dropped" : "")
    }

    private func filingJob(for finding: Finding) -> BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    /// What this finding is still asking, if anything. Filed, added to an issue, dropped or declined before are
    /// all answers — the queue fades them and the focus pane offers no buttons for them.
    private func decision(for finding: Finding) -> FindingDecision {
        if let job = filingJob(for: finding) {
            switch job.state {
            case .starting, .running: return FindingDecision(label: "filing…", isSettled: false, tone: .running)
            case .asking: return FindingDecision(label: "the run is asking", isSettled: false, tone: .waiting)
            case .ended(_, let failed):
                if failed { return FindingDecision(label: "filing failed", isSettled: false, tone: .failed) }
                return FindingDecision(label: "filed", isSettled: true, tone: .neutral)
            }
        }
        if let filed = finding.filing {
            return FindingDecision(label: filed.label.hasPrefix("#") ? "filed \(filed.label)" : filed.label.lowercased(),
                                   isSettled: true, tone: .neutral)
        }
        if model.isInLocalBacklog(finding.id) { return FindingDecision(label: "filed", isSettled: true, tone: .neutral) }
        if model.ignoredFindings.contains(finding.id) { return FindingDecision(label: "dropped", isSettled: true, tone: .neutral) }
        if finding.categories.contains(.closedOrDeclined) {
            return FindingDecision(label: "declined before", isSettled: true, tone: .neutral)
        }
        if finding.categories.contains(.needsDecision) {
            return FindingDecision(label: "needs a decision", isSettled: false, tone: .waiting)
        }
        if finding.categories.contains(.knownNewEvidence) {
            return FindingDecision(label: "an issue already covers it", isSettled: false, tone: .info)
        }
        return FindingDecision(label: "new · \(finding.kind.rawValue.lowercased())", isSettled: false, tone: .info)
    }

    var body: some View {
        // The shared filter panel on the left (ADR 0046 decision 18): which run, and which kind.
        HStack(spacing: 0) {
            filterPanel
            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    queue
                    focus
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        // The selection is of a finding on screen. Changing what is on screen must not leave the pane holding
        // one the queue no longer lists.
        .onChange(of: model.selectedRunID) { selectedID = nil }
        .onChange(of: model.findingKindFilter) { selectedID = nil }
        .onChange(of: model.showsIgnoredFindings) { selectedID = nil }
    }

    /// The shared header (ADR 0046 decision 14): the counts and the run, then what this report could not check,
    /// ··· for resetting, and Hunt for issues last.
    private var header: some View {
        ScreenHeader(.findings) {
            Text(summary)
        } tools: {
            if report.searchNote != nil { noteButton }
            // What builds up between runs — set-aside findings, and every report ever written — is cleared
            // from here, beside the button that adds to it.
            Menu {
                Button("Reset findings…") { model.present(.resetFindings) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Findings actions")
            RunFindingsButton(model: model, size: .small)
        }
    }

    private var noteButton: some View {
        Button { showsNote = true } label: {
            // Not an ⓘ: the header's one ⓘ explains the tab (ADR 0046 decision 14); this is the report's blind spots.
            Image(systemName: "eye.slash")
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What this report could not check")
        .accessibilityLabel("What this report could not check")
        .popover(isPresented: $showsNote) {
            Text(report.searchNote ?? "")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320)
                .padding(14)
        }
    }

    /// Run and Show, in the shared panel. Group by is gone with the sections it ordered: one finding at a time
    /// has no groups to sort into, and the queue is the report's own order.
    private var filterPanel: some View {
        var groups: [FilterGroup] = []
        if report.runs.count > 1 {
            groups.append(FilterGroup(key: "findings.run", title: "Run", kind: .pickOne,
                                      options: [FilterOption(id: "", label: "All runs", isOn: model.selectedRunID == nil)]
                                        + report.runs.map { run in
                                            FilterOption(id: run.id, label: run.label, isOn: model.selectedRunID == run.id,
                                                         help: runPlainText(run))
                                        },
                                      toggle: { model.selectedRunID = $0.isEmpty ? nil : $0 }))
        }
        var show = [FilterOption(id: "all", label: "All", isOn: !model.showsIgnoredFindings && model.findingKindFilter == nil,
                                 count: "\(runFindings.count - ignoredCount)")]
        show += FindingKind.allCases.map { kind in
            FilterOption(id: kind.rawValue, label: kind.plural,
                         isOn: !model.showsIgnoredFindings && model.findingKindFilter == kind,
                         count: "\(report.count(of: kind, run: model.selectedRunID))")
        }
        if ignoredCount > 0 || model.showsIgnoredFindings {
            show.append(FilterOption(id: "ignored", label: "Dropped", isOn: model.showsIgnoredFindings, count: "\(ignoredCount)"))
        }
        groups.append(FilterGroup(key: "findings.show", title: "Show", kind: .pickOne, options: show, toggle: { id in
            model.showsIgnoredFindings = id == "ignored"
            model.findingKindFilter = FindingKind(rawValue: id)
        }))
        return FilterPanel(title: "Report", storageKey: "findings", groups: groups)
    }

    private func runPlainText(_ run: FindingsRun) -> String {
        guard let revision = run.revision else { return "Run · \(run.label)" }
        return "Run · \(run.label) · rev \(revision)"
    }

    // MARK: - The queue

    /// How far through the run you are, then every finding in it. The bar is the only thing on the screen that
    /// says a hunt has an end.
    private var queue: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(queueStatus)
                    .font(DeskFont.mono(11.5))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                progressBar
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleFindings) { finding in
                        FindingRow(finding: finding, decision: decision(for: finding),
                                   isSelected: finding.id == selected?.id) { selectedID = finding.id }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .pullToRefresh(isRefreshing: model.isRefreshing) { await model.sync() }
            }
            .pullToRefreshSpace()
        }
        .frame(width: Self.queueWidth, alignment: .leading)
        .background(DeskColor.sidebar)   // an inner list is navigation, like Work's milestones
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var queueStatus: String {
        let run = model.selectedRunID ?? report.runs.first?.label ?? ""
        return run.isEmpty ? "\(decidedCount) of \(visibleFindings.count) decided"
                           : "\(run) · \(decidedCount) of \(visibleFindings.count) decided"
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DeskColor.controlBorder)
                Capsule()
                    .fill(DeskColor.accent)
                    .frame(width: proxy.size.width * CGFloat(decidedCount) / CGFloat(max(visibleFindings.count, 1)))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(decidedCount) of \(visibleFindings.count) decided")
    }

    // MARK: - The decision

    @ViewBuilder private var focus: some View {
        if let selected {
            FindingFocus(finding: selected, model: model, decision: decision(for: selected),
                         position: (index: (visibleFindings.firstIndex { $0.id == selected.id } ?? 0) + 1,
                                    total: visibleFindings.count),
                         next: next,
                         skip: { if let next { selectedID = next.id } })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Text(model.showsIgnoredFindings ? "Nothing is dropped in this run." : "No findings match this filter.")
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private extension FindingKind {
    /// What the Show chip calls the kind: "Defects", "Architecture".
    var plural: String { self.rawValue == "Defect" ? "Defects" : self.rawValue }
}

struct FindingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        FindingsPreviewHost()
            .frame(width: 1100, height: 780)
    }

    private struct FindingsPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            FindingsScreen(model: model)
                .task { await model.load() }
        }
    }
}
