import DeskCore
import SwiftUI

/// Work's left pane (ADR 0046 decisions 13, 16): the milestones in working order — the Plan, as a list — and the
/// filters, so everything that narrows the Board beside it is in one column. Collapses to a rail so a small screen gets the Board's width back.
struct WorkMilestonePane: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage("workMilestonesCollapsed") private var isCollapsed = false
    @State private var hovered: String?

    @AppStorage("workFoldedSections") private var foldedRaw = ""

    private var rows: [PlanRow] { model.visibleMilestoneRows }
    private var filter: TaskFilter { model.taskFilter }

    var body: some View {
        Group {
            if isCollapsed { rail } else { list }
        }
        .background(DeskColor.sidebar)   // navigation layer, like the app sidebar beside it
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    /// The whole rail is one button. The title is truncated to the rail's height BEFORE it is rotated: rotation does
    /// not change layout, so an unbounded title drew past its frame and covered the expand button (2026-09-19).
    /// With filters on it carries their count, so a collapsed list never hides that the Board is narrowed.
    private var rail: some View {
        Button { isCollapsed = false } label: {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 28, height: 28)
                if filter.activeCount > 0 {
                    Text("\(filter.activeCount)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DeskColor.accent))
                }
                Text(scopeTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 28, height: 220)
                Spacer()
            }
            .padding(.top, 10)
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(filter.activeCount > 0 ? "Show the milestones and filters — \(filter.summary) on" : "Show the milestones — \(scopeTitle)")
        .accessibilityLabel("Show the milestones")
    }

    /// Everything that narrows the Board, in one column (ADR 0046 decision 16): which milestones, then Priority,
    /// Type and Tag. Run roadmap and Clear all head it.
    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                DoorRunControl(model: model, door: "roadmap", title: "Run roadmap", size: .small)
                Spacer()
                if filter.activeCount > 0 {
                    Button("Clear all (\(filter.activeCount))") { model.taskFilter = TaskFilter() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DeskColor.accent)
                }
                Button { isCollapsed = true } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the list, for a wider Board")
                .accessibilityLabel("Hide the milestones")
            }
            .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section("Milestones", key: "milestones", note: "\(model.milestoneRows.filter { $0.title != nil }.count)", isOn: false) {
                        stageSwitch
                        milestoneItems
                    }
                    rule
                    section("Priority", key: "priority", note: note(filter.priorities.count), isOn: !filter.priorities.isEmpty) {
                        ForEach(TaskFilter.priorityOrder, id: \.self) { p in
                            option(p, tone: TaskCard.priorityTone(p), isOn: filter.priorities.contains(p),
                                   count: model.facetCount(.priority) { $0.priority == p }) {
                                toggle(\.priorities, p)
                            }
                        }
                        option("None", isOn: filter.priorities.contains(TaskFilter.unprioritised),
                               count: model.facetCount(.priority) { $0.priority == nil }) {
                            toggle(\.priorities, TaskFilter.unprioritised)
                        }
                    }
                    rule
                    section("Type", key: "type", note: note(filter.kinds.count), isOn: !filter.kinds.isEmpty) {
                        ForEach(TaskKind.allCases, id: \.self) { kind in
                            option(kind.rawValue, isOn: filter.kinds.contains(kind),
                                   count: model.facetCount(.kind) { $0.kind == kind }) {
                                toggle(\.kinds, kind)
                            }
                        }
                    }
                    rule
                    section("Tag", key: "tag", note: note(filter.tags.count), isOn: !filter.tags.isEmpty) {
                        ForEach(TaskFilter.tagLabels, id: \.self) { tag in
                            option(tag.capitalized, isOn: filter.tags.contains(tag),
                                   count: model.facetCount(.tag) { $0.labels.contains(tag) }) {
                                toggle(\.tags, tag)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 270)
    }

    // MARK: - Sections

    private var folded: Set<String> { Set(foldedRaw.split(separator: ",").map(String.init)) }

    private func note(_ on: Int) -> String? { on > 0 ? "\(on) on" : nil }

    /// A section that folds: ▾/▸, its name, and at the right its count — blue "1 on" while it is filtering. The fold
    /// is remembered.
    private func section<Content: View>(_ title: String, key: String, note: String?, isOn: Bool,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        let isFolded = folded.contains(key)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                var set = folded
                if isFolded { set.remove(key) } else { set.insert(key) }
                foldedRaw = set.sorted().joined(separator: ",")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(DeskColor.faintInk).frame(width: 10)
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskColor.secondaryInk)
                    Spacer()
                    if let note {
                        Text(note).font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? DeskColor.accent : DeskColor.faintInk)
                    }
                }
                .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(isFolded ? "folded" : "open")")
            if !isFolded { content() }
        }
    }

    private var rule: some View {
        Rectangle().fill(DeskColor.divider).frame(height: 1).padding(.horizontal, 6).padding(.top, 6)
    }

    /// One filter option: a checkbox, its dot, its name and a count that takes the other filters into account. At 0
    /// it is dimmed, so a click never lands on an empty Board — but still clickable, to turn it off.
    private func option(_ label: String, tone: StatusTone? = nil, isOn: Bool, count: Int,
                        action: @escaping () -> Void) -> some View {
        let dim = count == 0 && !isOn
        return Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? DeskColor.accent : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isOn ? DeskColor.accent : DeskColor.faintInk.opacity(0.6), lineWidth: 1.5))
                    .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.white) } }
                    .frame(width: 13, height: 13)
                if let tone { Circle().fill(DeskColor.tone(tone).dot).frame(width: 7, height: 7) }
                Text(label).font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
                Spacer()
                Text("\(count)").font(.system(size: 11.5).monospacedDigit())
            }
            .foregroundStyle(isOn ? DeskColor.accent : (dim ? DeskColor.faintInk.opacity(0.6) : DeskColor.ink))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle<T: Hashable>(_ path: WritableKeyPath<TaskFilter, Set<T>>, _ value: T) {
        var f = model.taskFilter
        if f[keyPath: path].contains(value) { f[keyPath: path].remove(value) } else { f[keyPath: path].insert(value) }
        model.taskFilter = f
    }

    // MARK: - Milestones

    /// All · Open · Working now. Open, the default, folds finished milestones into one line.
    private var stageSwitch: some View {
        HStack(spacing: 4) {
            ForEach(MilestoneStage.allCases, id: \.self) { stage in
                let on = model.milestoneStage == stage
                Button { model.milestoneStage = stage } label: {
                    Text(stage.rawValue)
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? DeskColor.accent : DeskColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? DeskColor.accent.opacity(0.12) : DeskColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? DeskColor.accent.opacity(0.45) : DeskColor.divider))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 6)
    }

    @ViewBuilder private var milestoneItems: some View {
        if model.milestoneStage != .workingNow {
            item(scope: .all, title: "All milestones", subtitle: "every open issue by stage", p0: 0, row: nil)
        }
        ForEach(rows.filter { $0.title != nil }) { row in
            item(scope: .milestone(row.title!), title: row.title!,
                 subtitle: subtitle(row), p0: row.priorityCounts.first { $0.priority == "P0" }?.count ?? 0, row: row)
        }
        if model.milestoneStage != .workingNow, let unplaced = rows.first(where: { $0.title == nil }) {
            item(scope: .noMilestone, title: "No milestone", subtitle: "\(unplaced.tasks.count) open",
                 p0: unplaced.priorityCounts.first { $0.priority == "P0" }?.count ?? 0, row: nil)
        }
        if model.milestoneStage == .open, model.finishedMilestoneCount > 0 {
            Button(model.showsFinishedMilestones ? "Hide finished milestones"
                   : "Show \(model.finishedMilestoneCount) finished milestone\(model.finishedMilestoneCount == 1 ? "" : "s")") {
                model.showsFinishedMilestones.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(DeskColor.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        if model.milestoneRows.allSatisfy({ $0.title == nil }) {
            Text("No milestones yet. The roadmap door proposes them from what this repository records, and asks before it files.")
                .font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                .fixedSize(horizontal: false, vertical: true).padding(10)
        }
    }

    private func subtitle(_ row: PlanRow) -> String {
        let done = "\(row.closed) of \(row.total) done"
        if ProjectWindowModel.isFinished(row) { return "Finished · \(done)" }
        return row.isWorkingNow ? "Working now · \(done)" : "Not started · \(done)"
    }

    private func item(scope: WorkScope, title: String, subtitle: String, p0: Int, row: PlanRow?) -> some View {
        let selected = model.effectiveWorkScope == scope
        let key = "\(scope)"
        return Button { model.workScope = scope } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(row?.isWorkingNow == true ? DeskColor.accent : Color.clear)
                    .frame(width: 7, height: 7).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk).lineLimit(1)
                    if let row, row.total > 0 {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DeskColor.divider)
                                Capsule().fill(DeskColor.tone(.running).dot)
                                    .frame(width: proxy.size.width * CGFloat(row.closed) / CGFloat(max(row.total, 1)))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if p0 > 0 {
                        PropertyChip("\(p0) P0", tone: .failed, verticalPadding: 0, horizontalPadding: 5)
                    }
                    if let row, !row.isWorkingNow, hovered == key {
                        Button("Move to top") { Task { await model.moveToTopOfPlan(row.title!) } }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                            .help("Make this the milestone being worked — Next up reads it. Stored on this Mac, not on GitHub.")
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? DeskColor.accent.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
        .contextMenu {
            if let row, !row.isWorkingNow {
                Button("Move to top") { Task { await model.moveToTopOfPlan(row.title!) } }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scopeTitle: String {
        switch model.effectiveWorkScope {
        case .all: return "All milestones"
        case .milestone(let title): return title
        case .noMilestone: return "No milestone"
        }
    }
}
