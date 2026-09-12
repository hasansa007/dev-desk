import DeskCore
import SwiftUI

struct FindingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            SurfaceView(snapshot.findings, fillsScreen: true) { report in
                if report.runs.isEmpty {
                    EmptyStateView(title: "No survey runs yet",
                                   message: "A survey writes its report to `docs/survey/`, and it appears here.") {
                        RunSurveyButton(model: model)
                    }
                } else {
                    FindingsSplitView(model: model, report: report)
                }
            }
        }
    }
}

/// Starts `dev:survey` as a run; the run's own pane asks for consent before anything executes.
private struct RunSurveyButton: View {
    let model: ProjectWindowModel
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    var body: some View {
        let blocked = model.runBlockedReason(agent: defaultConnection)
        Button("Run survey") { model.present(.runFocus("survey")) }
        .buttonStyle(DeskButtonStyle(kind: .primary, size: .smallWide))
        .disabled(blocked != nil)
        .help(blocked ?? "Start dev:survey in \(defaultConnection), in this project's folder")
    }
}

private struct FindingsSplitView: View {
    @Bindable var model: ProjectWindowModel
    let report: FindingsReport

    private var visibleFindings: [Finding] {
        report.findings
            .filter { model.selectedRunID == nil || $0.runID == model.selectedRunID }
            .filter { model.findingFilter == nil || $0.categories.contains(model.findingFilter!) }
    }

    /// Falls back to the first visible finding when the stored selection is filtered out; never writes back.
    private var selectedFinding: Finding? {
        visibleFindings.first { $0.id == model.selectedFindingID } ?? visibleFindings.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
            Group {
                if let finding = selectedFinding {
                    ScrollView {
                        FindingDetail(finding: finding, model: model)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("No findings match this filter.")
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
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleFindings) { finding in
                        FindingRow(finding: finding, isSelected: finding.id == selectedFinding?.id) {
                            model.selectedFindingID = finding.id
                        }
                    }
                    if let note = report.searchNote {
                        Text(note)
                            .font(DeskFont.small)
                            .foregroundStyle(DeskColor.faintInk)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                    }
                }
            }
        }
        .frame(width: 300, alignment: .leading)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Survey").font(DeskFont.section)
                Spacer()
                RunSurveyButton(model: model)
            }
            runLine
                .padding(.top, 8)
            FlowLayout(spacing: 5) {
                ForEach(FindingCategory.allCases, id: \.self) { category in
                    let isSelected = model.findingFilter == category
                    FindingFilterChip(title: "\(category.rawValue) \(report.count(of: category, run: model.selectedRunID))",
                                      category: category, isSelected: isSelected) {
                        model.findingFilter = isSelected ? nil : category
                    }
                }
            }
            .padding(.top, 9)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    @ViewBuilder private var runLine: some View {
        if report.runs.count > 1 {
            Picker("", selection: $model.selectedRunID) {
                ForEach(report.runs) { run in
                    Text(runPlainText(run)).tag(run.id as String?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Survey run")
        } else if let run = report.runs.first {
            MarkdownText(runMarkdownText(run), font: DeskFont.secondary, color: DeskColor.mutedInk)
        }
    }

    /// The label carries a report's file name, so it is escaped before it meets markdown.
    private func runMarkdownText(_ run: SurveyRun) -> String {
        guard let revision = run.revision else { return "Run · \(Markdown.escape(run.label))" }
        return "Run · \(Markdown.escape(run.label)) · rev `\(revision)`"
    }

    private func runPlainText(_ run: SurveyRun) -> String {
        guard let revision = run.revision else { return "Run · \(run.label)" }
        return "Run · \(run.label) · rev \(revision)"
    }
}

/// New findings carry the info tone (D:535); the active filter takes the accent fill the design uses for selected controls.
private struct FindingFilterChip: View {
    let title: String
    let category: FindingCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(DeskColor.accent, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
                    .fixedSize()
            } else {
                PropertyChip(title, tone: category == .new ? .info : .neutral,
                             fill: category == .new ? nil : DeskColor.neutralChipFill2, verticalPadding: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FindingRow: View {
    let finding: Finding
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(finding.id) \(finding.title)")
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                Text(finding.listDetail)
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
