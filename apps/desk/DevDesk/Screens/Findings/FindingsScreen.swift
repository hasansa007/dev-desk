import DeskCore
import SwiftUI

struct FindingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            SurfaceView(snapshot.findings) { report in
                if report.runs.isEmpty {
                    EmptyStateView(title: "No survey runs yet",
                                   message: "Run `/dev:survey` to write a report to `docs/survey/`; it appears here.")
                } else {
                    FindingsSplitView(model: model, report: report)
                }
            }
        }
    }
}

private struct FindingsSplitView: View {
    @Bindable var model: ProjectWindowModel
    let report: FindingsReport
    @State private var showSurveyPopover = false

    private var visibleFindings: [Finding] {
        report.findings
            .filter { model.selectedRunID == nil || $0.runID == model.selectedRunID }
            .filter { model.findingFilter == nil || $0.categories.contains(model.findingFilter!) }
    }

    private var selectedFinding: Finding? {
        report.findings.first { $0.id == model.selectedFindingID } ?? report.findings.first
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
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                }
            }
            if let note = report.searchNote {
                Text(note)
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.faintInk)
                    .lineSpacing(3)
                    .padding(14)
            }
        }
        .frame(width: 300, alignment: .leading)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Findings").font(DeskFont.section)
                Spacer()
                Button("Run survey") { showSurveyPopover = true }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .popover(isPresented: $showSurveyPopover) {
                        MarkdownText("Run `/dev:survey` in your coding agent. Its report lands in `docs/survey/`, and Dev Desk reads it from there.",
                                     font: DeskFont.secondary, color: DeskColor.secondaryInk)
                            .frame(width: 280)
                            .padding(12)
                    }
            }
            runLine
            FlowLayout(spacing: 5) {
                ForEach(FindingCategory.allCases, id: \.self) { category in
                    let isSelected = model.findingFilter == category
                    Button {
                        model.findingFilter = isSelected ? nil : category
                    } label: {
                        PropertyChip("\(category.rawValue) \(report.count(of: category, run: model.selectedRunID))",
                                     tone: isSelected ? .info : .neutral)
                    }
                    .buttonStyle(.plain)
                }
            }
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
        } else if let run = report.runs.first {
            MarkdownText(runMarkdownText(run), font: DeskFont.secondary, color: DeskColor.mutedInk)
        }
    }

    private func runMarkdownText(_ run: SurveyRun) -> String {
        guard let revision = run.revision else { return "Run · \(run.label)" }
        return "Run · \(run.label) · rev `\(revision)`"
    }

    private func runPlainText(_ run: SurveyRun) -> String {
        guard let revision = run.revision else { return "Run · \(run.label)" }
        return "Run · \(run.label) · rev \(revision)"
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

/// Wraps subviews left-to-right, starting a new row when the next one would overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Splits a two-sentence note into a bold lead and a supporting detail for `NoticeBanner`.
func splitLeadSentence(_ text: String) -> (title: String, message: String) {
    guard let range = text.range(of: ". ") else { return (text, "") }
    return (String(text[..<range.upperBound]), String(text[range.upperBound...]))
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
