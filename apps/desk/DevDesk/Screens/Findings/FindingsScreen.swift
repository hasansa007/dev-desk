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

/// The survey is a triage list: rows sectioned by what each finding asks of you, or by the file it points at,
/// with checkboxes so several can be filed or ignored at once. It was a grid of cards, and before that a list
/// beside a reading pane; the grid repeated itself on every card, and the reading pane left a finding as
/// something to read. The row keeps the actions on the finding and the dialog keeps the evidence.
private struct FindingsBoard: View {
    @Bindable var model: ProjectWindowModel
    let report: FindingsReport

    @State private var showsNote = false
    @State private var checked: Set<String> = []
    @State private var collapsed: Set<String> = []
    @AppStorage(PreferenceKey.surveyGrouping) private var groupingRaw = FindingGrouping.status.rawValue
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var grouping: FindingGrouping { FindingGrouping(rawValue: groupingRaw) ?? .status }

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

    private var groups: [FindingGroup] {
        FindingGroups.group(visibleFindings, by: grouping, filed: Set(visibleFindings.filter(isFiled).map(\.id)))
    }

    private func filingJob(for finding: Finding) -> BackgroundJob? {
        guard let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: finding.id, in: path)
    }

    /// On the board, or handed to the tracker by a run that finished cleanly.
    private func isFiled(_ finding: Finding) -> Bool {
        if model.isInLocalBacklog(finding.id) { return true }
        if let job = filingJob(for: finding), case .ended(_, false) = job.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            content
            if !checked.isEmpty { selectionBar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        // A selection is of rows on screen. Changing what is on screen must not leave a hidden row selected,
        // where "Add 3 to backlog" would file one nobody can see.
        .onChange(of: model.selectedRunID) { checked = [] }
        .onChange(of: model.findingKindFilter) { checked = [] }
        .onChange(of: model.showsIgnoredFindings) { checked = [] }
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

    /// Defect or architecture on the left, how the list is sectioned on the right. Status was a row of chips
    /// here too, but the sections are the status now, so a chip for each only filtered to one section.
    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Kind", selection: $model.findingKindFilter) {
                Text("All \(runFindings.count - ignoredCount)").tag(FindingKind?.none)
                ForEach(FindingKind.allCases, id: \.self) { kind in
                    Text("\(kind.rawValue) \(report.count(of: kind, run: model.selectedRunID))").tag(FindingKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if ignoredCount > 0 || model.showsIgnoredFindings {
                FindingFilterChip(title: "Ignored \(ignoredCount)", category: .closedOrDeclined,
                                  isSelected: model.showsIgnoredFindings) {
                    model.showsIgnoredFindings.toggle()
                }
            }
            Spacer(minLength: 0)
            Picker("Group", selection: $groupingRaw) {
                ForEach(FindingGrouping.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    @ViewBuilder private var content: some View {
        if visibleFindings.isEmpty {
            Text(model.showsIgnoredFindings ? "Nothing is ignored in this run." : "No findings match this filter.")
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups) { group in
                        Section {
                            if !collapsed.contains(group.id) {
                                // Keyed by section as well: grouped by file, one finding is a row in every file
                                // it names, and a lazy stack given the same id twice leaves blank rows.
                                ForEach(group.findings, id: \.id) { finding in
                                    FindingRow(finding: finding, model: model, isChecked: binding(for: finding.id),
                                               lines: grouping == .file ? (group.lines[finding.id] ?? "—") : nil)
                                        .id("\(group.id)/\(finding.id)")
                                }
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                // A new list per grouping. The lazy stack otherwise keeps the rows it built for the other
                // grouping — same finding ids — and shows by-status rows under by-file headers.
                .id(grouping)
                .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 18, trailing: 16))
                .pullToRefresh(isRefreshing: model.isRefreshing) { await model.load() }
            }
            .pullToRefreshSpace()
        }
    }

    /// The section's name, its count, and what the section means — said once here rather than on every row.
    /// Its checkbox selects the whole section, which is how a run's sixteen new findings are filed together.
    private func groupHeader(_ group: FindingGroup) -> some View {
        let ids = Set(group.findings.map(\.id))
        let allChecked = !ids.isEmpty && ids.isSubset(of: checked)
        let isCollapsed = collapsed.contains(group.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { allChecked },
                                     set: { if $0 { checked.formUnion(ids) } else { checked.subtract(ids) } }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: FindingRow.Width.check)
                .accessibilityLabel("Select every finding in \(group.title)")
            Button {
                if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DeskColor.mutedInk)
                        .frame(width: 10)
                    if let category = group.category {
                        StatusDot(tone: FindingTone.of(category), size: 7)
                    }
                    if grouping == .file {
                        Text(group.title)
                            .font(DeskFont.mono(11.5, weight: .semibold))
                            .foregroundStyle(DeskColor.ink)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text(group.title.uppercased())
                            .font(DeskFont.label)
                            .tracking(0.66)
                            .foregroundStyle(DeskColor.secondaryInk)
                    }
                    Text("\(group.findings.count)")
                        .font(DeskFont.label)
                        .foregroundStyle(DeskColor.faintInk)
                    if let note = groupNote(group) {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(DeskColor.mutedInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.title), \(group.findings.count) findings")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// What a status section is asking, and how far its findings were verified when they all agree.
    private func groupNote(_ group: FindingGroup) -> String? {
        let meaning: String?
        switch group.category {
        case .new: meaning = "not filed yet"
        case .knownNewEvidence: meaning = "an issue already covers these"
        case .needsDecision: meaning = "not confirmed — filed only if you choose to"
        case .closedOrDeclined: meaning = "decided against before"
        case nil: meaning = group.id == "filed" ? "each row says where its card is now" : nil
        }
        let parts = [meaning, group.sharedVerification].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { checked.contains(id) },
                set: { if $0 { checked.insert(id) } else { checked.remove(id) } })
    }

    private var checkedFindings: [Finding] { visibleFindings.filter { checked.contains($0.id) } }

    /// Only the checked findings that can be filed right now: one already filing, filed or in the backlog is
    /// left alone rather than drafted a second time.
    private var fileable: [Finding] {
        checkedFindings.filter {
            model.fileBlockedReason(key: $0.id, job: filingJob(for: $0), agent: defaultConnection) == nil
        }
    }

    private var selectionBar: some View {
        let count = checkedFindings.count
        let toFile = fileable
        return HStack(spacing: 10) {
            Text("\(count) selected")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
            Button("Clear") { checked = [] }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            Spacer(minLength: 0)
            if model.showsIgnoredFindings {
                Button("Stop ignoring") {
                    checkedFindings.forEach { model.restoreFinding($0.id) }
                    checked = []
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            } else {
                Button("Ignore") {
                    checkedFindings.forEach { model.ignoreFinding($0.id) }
                    checked = []
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                Button(toFile.count == count ? "Add \(count) to backlog" : "Add \(toFile.count) of \(count) to backlog") {
                    toFile.forEach { model.fileToBacklog($0.backlogDraft, jobs: jobs, agent: defaultConnection) }
                    checked = []
                }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                .disabled(toFile.isEmpty)
                .help(toFile.count == count ? model.backlogDestination
                      : "The rest are already filing, filed, or in docs/backlog/")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(DeskColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
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
