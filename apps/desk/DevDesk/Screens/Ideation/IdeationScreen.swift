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

    private var split: some View {
        HStack(spacing: 0) {
            listPane
            Group {
                if let selected {
                    ScrollView {
                        OpportunityDetail(opportunity: selected, model: model)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("No opportunities match this filter.")
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.mutedInk)
                        .padding(18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { opportunity in
                        OpportunityRow(opportunity: opportunity, isSelected: opportunity.id == selected?.id) {
                            model.selectedOpportunityID = opportunity.id
                        }
                    }
                }
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


private struct OpportunityRow: View {
    let opportunity: Opportunity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.secondaryInk)
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

    /// Gain over cost is the ranking, so the row leads with both when the report gave them.
    private var detail: String {
        let parts = [opportunity.gain.map { "gain \($0)" }, opportunity.cost.map { "cost \($0)" }].compactMap { $0 }
        return parts.isEmpty ? opportunity.verdict.rawValue : "\(opportunity.verdict.rawValue) · \(parts.joined(separator: " · "))"
    }
}

private struct OpportunityDetail: View {
    let opportunity: Opportunity
    let model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownText(opportunity.title, font: .system(size: 17, weight: .semibold), color: DeskColor.ink)
                        .frame(maxWidth: 720, alignment: .leading)
                    if let proposed = opportunity.proposed {
                        MarkdownText("→ \(proposed)", color: DeskColor.secondaryInk)
                            .lineSpacing(5)
                            .frame(maxWidth: 720, alignment: .leading)
                    }
                    if !opportunity.summary.isEmpty {
                        MarkdownText(opportunity.summary, color: DeskColor.secondaryInk)
                            .lineSpacing(5)
                            .frame(maxWidth: 720, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    PropertyChip(opportunity.verdict.rawValue, verticalPadding: 2, horizontalPadding: 9)
                    if opportunity.verdict == .confirmed {
                        Button("File…") { file() }
                            .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                            .disabled(fileBlockedReason != nil)
                            .help(fileBlockedReason
                                  ?? model.backlogDestination)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                valueCard("Gain", opportunity.gain ?? "not stated")
                valueCard("Cost", opportunity.cost ?? "not stated")
                valueCard("Doing nothing", opportunity.doingNothing ?? "not stated")
            }
            .padding(.top, 16)
            HStack(alignment: .top, spacing: 14) {
                locationsCard
                limitsCard
            }
            .padding(.top, 14)
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

    private func valueCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            MarkdownText(value, font: .system(size: 12.5), color: DeskColor.secondaryInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }

    private var locationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Source locations")
            if opportunity.locations.isEmpty {
                Text("No source locations recorded.")
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.secondaryInk)
            } else {
                Text(opportunity.locations.joined(separator: "\n"))
                    .font(DeskFont.mono(11.5))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Verification limits")
            MarkdownText(opportunity.limits, font: .system(size: 12.5), color: DeskColor.secondaryInk)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
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
