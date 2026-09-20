import DeskCore
import SwiftUI

/// Settings is an index and one pane, not a scroll. The alternative — every section stacked in one long
/// scroll with a jump bar — was rejected twice over: the dialog is a fixed 660 pt and these sections are far
/// longer than that between them, so "reachable without scrolling past things you do not care about" would be
/// exactly what it broke; and two of the panes are editors with a lifecycle (`Run project` debounces into
/// `.devdesk/run.json` and flushes on disappear, `Work` loads from the snapshot on appear), so stacking them
/// would read and arm every project file the moment Settings opened.
///
/// What the index gains over the plain list it replaces is a filter: the developer hunting for the agent limit
/// types "agent", not "Execution", and the row answers with the phrase it matched.
///
/// `model` is nil on Home, where no project is selected (ADR 0050) and ⌘, used to do nothing. The sections
/// that exist only for a project are then ABSENT, not greyed: a Run project pane with no project is a shell,
/// and a shell is the lie this rewrite is about. Selection lives in the model when there is one, so returning
/// to a project reopens where you left it, and in the view when there is not.
struct SettingsScreen: View {
    let model: ProjectWindowModel?
    @State private var query = ""
    /// Home's selection. Never written when a project is open, so the two never disagree.
    @State private var appSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            index
            ScrollView {
                pane
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeskColor.canvas)
        }
    }

    // MARK: - The index

    private var results: [SettingsMatch] {
        SettingsIndex.search(query).filter { model != nil || SettingsIndex.existsWithoutProject($0.section) }
    }

    private var selection: Binding<SettingsSection> {
        guard let model else { return $appSection }
        return Binding(get: { model.settingsSection }, set: { model.settingsSection = $0 })
    }

    private var index: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty {
                        Text("Nothing matches “\(query)”.")
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.faintInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    } else if query.isEmpty && model != nil {
                        // Grouped by where a setting applies (ADR 0046): every project on this Mac, or only
                        // this one. A search drops the groups, because a match is a match either way — and so
                        // does Home, where "this project" would head an empty group.
                        group("This Mac", results.filter { !$0.section.isProjectScoped })
                        group("This project", results.filter(\.section.isProjectScoped)).padding(.top, 12)
                    } else {
                        ForEach(results) { row($0.section, matches: $0.matches) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(width: DeskMetric.sidebarWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.sidebar)   // navigation layer (the three-layer rule)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(DeskFont.mono(11))
                .foregroundStyle(DeskColor.faintInk)
                .accessibilityHidden(true)
            TextField("Find a setting", text: $query)
                .textFieldStyle(.plain)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.ink)
                .accessibilityLabel("Find a setting")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.faintInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .controlChrome(fill: DeskColor.canvas, height: DeskMetric.controlHeight)
    }

    private func group(_ title: String, _ rows: [SettingsMatch]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            ForEach(rows) { row($0.section, matches: $0.matches) }
        }
    }

    /// One entry: what it is called, what is under it, and — when it matched a search — the phrase it matched
    /// on, so a result never leaves you to guess which of its settings you were looking for.
    private func row(_ section: SettingsSection, matches: [String]) -> some View {
        let isSelected = selection.wrappedValue == section
        return Button { selection.wrappedValue = section } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: SettingsIndex.symbol(section))
                    .font(DeskFont.mono(12))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isSelected ? DeskColor.onColorInk : DeskColor.mutedInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(DeskFont.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? DeskColor.onColorInk : DeskColor.navInk)
                        .lineLimit(1)
                    if let hint = hint(for: section, matches: matches) {
                        Text(hint)
                            .font(DeskFont.mono(10.5))
                            .foregroundStyle(isSelected ? DeskColor.onColorInk.opacity(0.75) : DeskColor.faintInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if needsAttention(section) {
                    StatusDot(tone: .failed, size: 6).padding(.top, 5)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(SettingsIndex.blurb(section))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// While searching, the matched phrase; otherwise nothing — a blurb under all ten entries at once pushes
    /// the tenth below the fold, which is the scroll the index exists to avoid.
    private func hint(for section: SettingsSection, matches: [String]) -> String? {
        guard !query.isEmpty else { return nil }
        return matches.isEmpty ? SettingsIndex.blurb(section) : matches.prefix(2).joined(separator: " · ")
    }

    /// A red dot on the index means the pane has something wrong in it that is not visible from here. Only
    /// a real fault earns one: an unavailable connection is a fault, a sample project having no folder is not.
    private func needsAttention(_ section: SettingsSection) -> Bool {
        guard section == .accountsAndConnections || section == .agentsAndDefaults else { return false }
        return model?.snapshot?.connections.contains { $0.state == .unavailable } ?? false
    }

    /// The four project-only panes are unreachable without a model — the index does not list them on Home —
    /// but the switch still has to be total, and falling through to the first app-wide section is the one
    /// answer that cannot show an empty pane if a stale selection ever survives a project closing.
    @ViewBuilder private var pane: some View {
        switch selection.wrappedValue {
        case .general: GeneralPane(model: model)
        case .appearance: AppearancePane()
        case .agentsAndDefaults: AgentsAndDefaultsPane(model: model)
        case .startWith: StartWithPane()
        case .notifications: NotificationsPane()
        case .execution: ExecutionPane()
        case .accountsAndConnections:
            if let model { AccountsPane(model: model) } else { GeneralPane(model: nil) }
        case .work:
            if let model { WorkSettingsPane(model: model) } else { GeneralPane(model: nil) }
        case .projectOverrides:
            if let model { ProjectOverridesPane(model: model) } else { GeneralPane(model: nil) }
        case .runProject:
            if let model { RunProjectPane(model: model) } else { GeneralPane(model: nil) }
        }
    }
}

struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPreviewHost()
            .frame(width: 860, height: 520)
    }

    private struct SettingsPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            SettingsScreen(model: model)
                .task {
                    await model.load()
                    model.settingsSection = .execution
                }
        }
    }
}
