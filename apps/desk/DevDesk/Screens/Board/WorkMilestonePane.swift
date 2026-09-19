import DeskCore
import SwiftUI

/// Work's left pane (ADR 0046 decision 13): the milestones in working order — the Plan, as a list — and the choice
/// of which one the Board beside it shows. Collapses to a rail so a small screen gets the Board's width back.
struct WorkMilestonePane: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage("workMilestonesCollapsed") private var isCollapsed = false
    @State private var hovered: String?

    private var rows: [PlanRow] { model.planRows }

    var body: some View {
        Group {
            if isCollapsed { rail } else { list }
        }
        .background(DeskColor.headerFill)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private var rail: some View {
        VStack(spacing: 10) {
            Button { isCollapsed = false } label: {
                Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the milestones")
            .accessibilityLabel("Show the milestones")
            Text(scopeTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeskColor.mutedInk)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 220)
            Spacer()
        }
        .padding(.top, 10)
        .frame(width: 36)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Milestones").font(DeskFont.secondary.weight(.semibold)).foregroundStyle(DeskColor.secondaryInk)
                Spacer()
                Button { isCollapsed = true } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the milestones, for a wider Board")
                .accessibilityLabel("Hide the milestones")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    item(scope: .all, title: "All milestones", subtitle: "every open issue by stage", p0: 0, row: nil)
                    ForEach(rows.filter { $0.title != nil }) { row in
                        item(scope: .milestone(row.title!), title: row.title!,
                             subtitle: subtitle(row), p0: row.priorityCounts.first { $0.priority == "P0" }?.count ?? 0, row: row)
                    }
                    if let unplaced = rows.first(where: { $0.title == nil }) {
                        item(scope: .noMilestone, title: "No milestone", subtitle: "\(unplaced.tasks.count) open",
                             p0: unplaced.priorityCounts.first { $0.priority == "P0" }?.count ?? 0, row: nil)
                    }
                    if rows.allSatisfy({ $0.title == nil }) {
                        Text("No milestones yet. The roadmap door proposes them from what this repository records, and asks before it files.")
                            .font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                            .fixedSize(horizontal: false, vertical: true).padding(10)
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider()
            DoorRunControl(model: model, door: "roadmap", title: "Run roadmap", size: .small)
                .padding(10)
        }
        .frame(width: 270)
    }

    private func subtitle(_ row: PlanRow) -> String {
        let done = "\(row.closed) of \(row.total) done"
        return row.isWorkingNow ? "Working now · \(done)" : "\(row.tasks.count) open · \(done)"
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
