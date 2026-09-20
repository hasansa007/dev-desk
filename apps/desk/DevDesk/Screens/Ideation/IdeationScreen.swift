import DeskCore
import SwiftUI

struct IdeationScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            if case .available(let report) = snapshot.ideation, !report.runs.isEmpty {
                IdeationSplitView(model: model, report: report)
            } else {
                // The same header before the first run (ADR 0046 decision 14).
                VStack(spacing: 0) {
                    ScreenHeader(.ideation) { EmptyView() } tools: { GenerateIdeasButton(model: model, size: .small) }
                    SurfaceView(snapshot.ideation, fillsScreen: true) { _ in
                        EmptyStateView(title: "No ideation runs yet",
                                       message: "An ideation run writes its report to `docs/ideation/`, and it appears here.") {
                            GenerateIdeasButton(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(DeskColor.canvas)
            }
        }
    }
}

/// Starts `dev:ideation` as a run, with the kinds the developer left on; none selected means the door's own default, all three.
private struct GenerateIdeasButton: View {
    let model: ProjectWindowModel
    var size: DeskButtonStyle.Size = .regular
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection

    var body: some View {
        DoorRunControl(model: model, door: "ideation", title: "Generate ideas", size: size)
    }
}

/// The door's three kinds; each is a flag it reads, and leaving all off is how it covers everything.
enum IdeationKind: String, CaseIterable, Hashable {
    case performance, security, quality

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var argument: String {
        switch self {
        case .performance: return "--perf"
        case .security: return "--security"
        case .quality: return "--quality"
        }
    }
}

private struct IdeationSplitView: View {
    @Bindable var model: ProjectWindowModel
    let report: IdeationReport

    private var visible: [Opportunity] {
        report.opportunities
            .filter { model.selectedIdeationRunID == nil || $0.runID == model.selectedIdeationRunID }
            .filter { model.ideationFilter == nil || $0.verdict == model.ideationFilter }
    }

    /// Falls back to the first visible opportunity when the stored selection is filtered out; never writes back.
    private var selected: Opportunity? {
        visible.first { $0.id == model.selectedOpportunityID } ?? visible.first
    }

    var body: some View {
        // The shared filter panel (ADR 0046 decision 18), then the header over the idea list and its detail.
        HStack(spacing: 0) {
            filterPanel
            VStack(spacing: 0) {
                ScreenHeader(.ideation) {
                    Text("\(visible.count) idea\(visible.count == 1 ? "" : "s")")
                } tools: {
                    GenerateIdeasButton(model: model, size: .small)
                }
                split
            }
        }
        .background(DeskColor.canvas)
    }

    private var filterPanel: some View {
        var groups: [FilterGroup] = []
        if report.runs.count > 1 {
            groups.append(FilterGroup(key: "ideation.run", title: "Run", kind: .pickOne,
                                      options: report.runs.map { run in
                                          FilterOption(id: run.id, label: run.label, isOn: model.selectedIdeationRunID == run.id,
                                                       help: label(run))
                                      },
                                      toggle: { model.selectedIdeationRunID = $0 }))
        }
        groups.append(FilterGroup(key: "ideation.verdict", title: "Verdict", kind: .filter,
                                  options: verdictCounts.map { entry in
                                      FilterOption(id: entry.verdict.rawValue, label: entry.verdict.rawValue,
                                                   isOn: model.ideationFilter == entry.verdict, count: "\(entry.count)")
                                  },
                                  toggle: { id in
                                      let verdict = OpportunityVerdict(rawValue: id)
                                      model.ideationFilter = model.ideationFilter == verdict ? nil : verdict
                                  }))
        return FilterPanel(title: "Ideas", storageKey: "ideation", groups: groups,
                           clear: model.ideationFilter.map { verdict in (verdict.rawValue, 1, { model.ideationFilter = nil }) })
    }

    private var verdictCounts: [(verdict: OpportunityVerdict, count: Int)] {
        OpportunityVerdict.allCases
            .map { (verdict: $0, count: report.count(of: $0, run: model.selectedIdeationRunID)) }
            .filter { $0.count > 0 }
    }

    /// The queue on the left, the idea you are deciding on the right — the same shape Findings takes, because
    /// both screens ask the same thing: one yes/no at a time, not a list of them (2026-09-20).
    private var split: some View {
        HStack(spacing: 0) {
            listPane
            Group {
                if let selected {
                    OpportunityFocus(opportunity: selected, model: model, next: next(after: selected),
                                     skip: { if let next = next(after: selected) { model.selectedOpportunityID = next.id } })
                } else {
                    Text("No opportunities match this filter.")
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.mutedInk)
                        .padding(18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// The next idea in the run — what "Not now" moves to, so a pass is a step rather than a dead end.
    private func next(after opportunity: Opportunity) -> Opportunity? {
        let rest = visible.drop { $0.id != opportunity.id }.dropFirst()
        return rest.first ?? visible.first { $0.id != opportunity.id }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(visible.count) idea\(visible.count == 1 ? "" : "s") in this run")
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { opportunity in
                        OpportunityRow(opportunity: opportunity, isSelected: opportunity.id == selected?.id) {
                            model.selectedOpportunityID = opportunity.id
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 320, alignment: .leading)
        .background(DeskColor.sidebar)   // an inner list is navigation, like Work's milestones
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private func label(_ run: IdeationRun) -> String {
        run.kinds.map { "Run · \(run.label) · \($0)" } ?? "Run · \(run.label)"
    }
}

/// One idea in the queue: how far it was verified, what it is called, and what it is worth against what it costs.
private struct OpportunityRow: View {
    let opportunity: Opportunity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(tone: OpportunityFocus.tone(of: opportunity.verdict), size: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(DeskColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(detail)
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 48, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.neutralChipFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .contentShape(Rectangle())
            // An idea already decided against is still listed, faded — that is what says it was considered.
            .opacity(opportunity.verdict == .refuted || opportunity.verdict == .declined ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(opportunity.title)
        .accessibilityLabel("\(opportunity.title), \(detail)")
    }

    /// Gain over cost is the ranking, so the row leads with both when the report gave them.
    private var detail: String {
        let parts = [opportunity.gain.map { "gain \($0.lowercased())" }, opportunity.cost.map { "cost \($0.lowercased())" }].compactMap { $0 }
        let verdict = opportunity.verdict.rawValue.lowercased()
        return parts.isEmpty ? verdict : "\(verdict) · \(parts.joined(separator: " · "))"
    }
}

/// One idea, in front of you, with its decision under it — file it, or not now. It was a detail pane beside a
/// list, where the title, the numbers and the File button all read as the same weight; here the question is
/// the biggest thing on the screen and the three numbers that answer it sit under it (2026-09-20).
private struct OpportunityFocus: View {
    let opportunity: Opportunity
    let model: ProjectWindowModel
    let next: Opportunity?
    let skip: () -> Void
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection

    /// The width the eye reads a paragraph at, plus the three value tiles that sit under it.
    private static let column: CGFloat = 720

    /// Confirmed is a fact about the check, not about a run: blue, never the reserved green.
    static func tone(of verdict: OpportunityVerdict) -> StatusTone {
        switch verdict {
        case .confirmed: return .info
        case .plausible: return .waiting
        case .refuted, .declined: return .neutral
        case .tracked: return .ended
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    StatusPill(badge: StatusBadge(Self.tone(of: opportunity.verdict), opportunity.verdict.rawValue))
                    Spacer(minLength: 8)
                    Text("run \(opportunity.runID)")
                        .font(DeskFont.mono(11.5))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                MarkdownText(opportunity.title, font: .system(size: 28, weight: .bold), color: DeskColor.ink)
                    .lineSpacing(2)
                if let proposed = opportunity.proposed {
                    MarkdownText("→ \(proposed)", font: DeskFont.mono(13), color: DeskColor.tone(.info).foreground)
                        .lineSpacing(4)
                }
                if !opportunity.summary.isEmpty {
                    MarkdownText(opportunity.summary, font: .system(size: 15), color: DeskColor.secondaryInk)
                        .lineSpacing(6)
                }
                HStack(alignment: .top, spacing: 12) {
                    valueCard("Gain", opportunity.gain)
                    valueCard("Cost", opportunity.cost)
                    valueCard("Doing nothing", opportunity.doingNothing)
                }
                HStack(alignment: .top, spacing: 12) {
                    locationsCard
                    limitsCard
                }
                decisions
            }
            .frame(width: Self.column, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Only a confirmed opportunity can be filed: a plausible one is held in the report with its reason, by design.
    /// Filing needs a tracker to file into and an agent to do it; naming which one is missing beats a
    /// button that is dim for no stated reason.
    private var fileBlockedReason: String? {
        model.fileBlockedReason(key: opportunity.id, job: nil, agent: defaultConnection)
    }

    private func file() {
        model.fileToBacklog(opportunity.backlogDraft, jobs: jobs, agent: defaultConnection)
    }

    @ViewBuilder private var decisions: some View {
        HStack(spacing: 10) {
            if opportunity.verdict == .confirmed {
                Button("File it…") { file() }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .decisionPrimary))
                    .disabled(fileBlockedReason != nil)
                    .help(fileBlockedReason ?? model.backlogDestination)
            }
            Button(opportunity.verdict == .confirmed ? "Not now" : "Next") { skip() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .decision))
                .disabled(next == nil)
                .help(next.map { "Leave this one and read \($0.title)" } ?? "This is the last idea in the run")
            Spacer(minLength: 8)
            Text(next.map { "next: \($0.title)" } ?? "the last idea in this run")
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
        }
    }

    /// The three numbers the decision rests on, read as numbers: the value large, the reason under it.
    private func valueCard(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            MarkdownText(value ?? "—", font: DeskFont.mono(19, weight: .semibold), color: DeskColor.ink)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 14)
    }

    private var locationsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Source locations")
            if opportunity.locations.isEmpty {
                Text("No source locations recorded.")
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.secondaryInk)
            } else {
                Text(opportunity.locations.joined(separator: "\n"))
                    .font(DeskFont.mono(11.5))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 14)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Verification limits")
            MarkdownText(opportunity.limits, font: .system(size: 12.5), color: DeskColor.secondaryInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 14)
    }
}

struct IdeationScreen_Previews: PreviewProvider {
    static var previews: some View {
        IdeationPreviewHost()
            .frame(width: 1100, height: 780)
    }

    private struct IdeationPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            IdeationScreen(model: model)
                .task {
                    await model.load()
                    model.go(.ideation)
                }
        }
    }
}
