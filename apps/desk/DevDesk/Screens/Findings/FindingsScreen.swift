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
                    FindingsBoard(model: model, report: report)
                }
            }
        }
    }
}

/// Starts `dev:survey` as a run; the run's own pane asks for consent before anything executes.
private struct RunSurveyButton: View {
    let model: ProjectWindowModel
    var size: DeskButtonStyle.Size = .regular

    var body: some View {
        DoorRunControl(model: model, door: "survey", title: "Run survey", size: size)
    }
}

/// The survey reads like the board: a header bar, filters, and cards. It was a list beside a reading pane,
/// which made a finding something you read rather than something you do something about.
private struct FindingsBoard: View {
    @Bindable var model: ProjectWindowModel
    let report: FindingsReport

    @State private var showsNote = false

    private let columns = [GridItem(.adaptive(minimum: 268, maximum: 400), spacing: 12, alignment: .top)]

    private var runFindings: [Finding] {
        report.findings.filter { model.selectedRunID == nil || $0.runID == model.selectedRunID }
    }

    private var ignoredCount: Int { runFindings.filter { model.ignoredFindings.contains($0.id) }.count }

    /// Ignored findings are out of every category list until the Ignored chip is on, and then they are the
    /// list: setting something aside that keeps appearing under "New" has not been set aside.
    private var visibleFindings: [Finding] {
        runFindings
            .filter { model.ignoredFindings.contains($0.id) == model.showsIgnoredFindings }
            .filter { model.findingFilter == nil || $0.categories.contains(model.findingFilter!) }
            .filter { model.findingKindFilter == nil || $0.kind == model.findingKindFilter }
    }

    private var summary: String {
        let total = runFindings.count
        return "\(total) finding\(total == 1 ? "" : "s")" + (ignoredCount > 0 ? " · \(ignoredCount) ignored" : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Survey")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Text(summary)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
            runControl
            if report.searchNote != nil { noteButton }
            Spacer(minLength: 0)
            // What builds up between runs — set-aside findings, and every report ever written — is cleared
            // from here, beside the button that adds to it.
            Menu {
                Button("Reset survey…") { model.present(.resetSurvey) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Survey actions")
            RunSurveyButton(model: model, size: .small)
        }
        .screenHeaderBar()
    }

    /// A menu, not a Picker. A `.menu` Picker with a long label stretched to the width of the pane and put its
    /// chevron at the far edge — a control the width of the screen, for a choice between two dates.
    @ViewBuilder private var runControl: some View {
        if report.runs.count > 1 {
            Menu {
                ForEach(report.runs) { run in
                    Button(runPlainText(run)) { model.selectedRunID = run.id }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(report.runs.first { $0.id == model.selectedRunID }.map(runPlainText) ?? "All runs")
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(DeskColor.border))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Survey run")
        } else if let run = report.runs.first {
            Text(runPlainText(run))
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
        }
    }

    private var noteButton: some View {
        Button { showsNote = true } label: {
            Image(systemName: "info.circle")
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

    private var filters: some View {
        FlowLayout(spacing: 5) {
            ForEach(FindingCategory.allCases, id: \.self) { category in
                let isSelected = model.findingFilter == category
                FindingFilterChip(title: "\(category.rawValue) \(report.count(of: category, run: model.selectedRunID))",
                                  category: category, isSelected: isSelected) {
                    model.findingFilter = isSelected ? nil : category
                }
            }
            // The other half of what a finding is: which side of the report it came out of. It filters beside
            // the categories rather than inside them — "New" and "Architecture" are two questions about one
            // finding, so a category and a kind can be on together.
            ForEach(FindingKind.allCases, id: \.self) { kind in
                let isSelected = model.findingKindFilter == kind
                FindingFilterChip(title: "\(kind.rawValue) \(report.count(of: kind, run: model.selectedRunID))",
                                  isSelected: isSelected) {
                    model.findingKindFilter = isSelected ? nil : kind
                }
            }
            if ignoredCount > 0 || model.showsIgnoredFindings {
                FindingFilterChip(title: "Ignored \(ignoredCount)", category: .closedOrDeclined,
                                  isSelected: model.showsIgnoredFindings) {
                    model.showsIgnoredFindings.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder private var content: some View {
        if visibleFindings.isEmpty {
            Text(model.showsIgnoredFindings ? "Nothing is ignored in this run." : "No findings match this filter.")
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(visibleFindings) { finding in
                        FindingCard(finding: finding, model: model)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 18, trailing: 16))
                .pullToRefresh(isRefreshing: model.isRefreshing) { await model.load() }
            }
            .pullToRefreshSpace()
        }
    }

    private func runPlainText(_ run: SurveyRun) -> String {
        guard let revision = run.revision else { return "Run · \(run.label)" }
        return "Run · \(run.label) · rev \(revision)"
    }
}

/// New findings carry the info tone (D:535); the active filter takes the accent fill the design uses for selected controls.
private struct FindingFilterChip: View {
    let title: String
    /// The category this chip filters by, when it filters by one. A kind chip passes none: it is neutral,
    /// because only "New" carries the info tone and a kind is not a category.
    var category: FindingCategory?
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
