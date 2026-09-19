import DeskCore
import SwiftUI

/// The Plan (ADR 0046; the destination keeps its stored name, `roadmap`). One row per milestone, top to bottom, in
/// the order you work them: the top row is Working now and feeds the Board's Next up. It was ten milestone columns
/// scrolled sideways, with security issues pulled out of their milestones into a column of their own.
struct RoadmapScreen: View {
    @Bindable var model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var isRoadmapRunning: Bool {
        if model.isDoorRunning("roadmap") { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveJob(door: "roadmap", in: path) ?? false
    }

    var body: some View {
        if let snapshot = model.snapshot {
            SurfaceView(snapshot.roadmap, fillsScreen: true) { roadmap in
                if roadmap.milestones.isEmpty {
                    EmptyStateView(title: isRoadmapRunning ? "The roadmap door is running" : "No plan yet",
                                   message: isRoadmapRunning
                                       ? "It is reading this repository's recorded gaps now. Milestones appear here once it files, and it asks before it does."
                                       : "A plan is this repository's open milestones, in the order you work them. The roadmap door proposes them from what the repository already records, and asks before it files.") {
                        DoorRunControl(model: model, door: "roadmap", title: "Run roadmap")
                    }
                } else {
                    PlanContent(model: model)
                }
            }
        }
    }
}

private struct PlanContent: View {
    @Bindable var model: ProjectWindowModel
    @State private var expanded: Set<String> = []
    @State private var didOpenWorking = false

    private var rows: [PlanRow] { model.planRows }

    var body: some View {
        VStack(spacing: 0) {
            header
            TaskFilterBar(model: model)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if rows.isEmpty {
                        Text("No milestone has an issue matching these filters.")
                            .font(DeskFont.body).foregroundStyle(DeskColor.mutedInk).padding(.top, 8)
                    }
                    ForEach(rows) { row in
                        PlanRowView(row: row, model: model, isExpanded: expanded.contains(row.id),
                                    reason: row.isWorkingNow ? model.snapshot?.activeMilestoneReason : nil) {
                            if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        .onAppear {
            // The working milestone opens by itself the first time: it is the one you came here to read.
            guard !didOpenWorking, let working = rows.first(where: \.isWorkingNow) else { return }
            expanded.insert(working.id)
            didOpenWorking = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Plan").font(DeskFont.section).foregroundStyle(DeskColor.ink)
            Text(summary).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 0)
            TextField("Search issues", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(DeskFont.secondary)
                .padding(.horizontal, 10)
                .frame(width: 200, alignment: .leading)
                .controlChrome()
            DoorRunControl(model: model, door: "roadmap", title: "Run roadmap", size: .small)
        }
        .screenHeaderBar()
    }

    private var summary: String {
        let milestones = rows.filter { $0.title != nil }.count
        return "\(milestones) milestone\(milestones == 1 ? "" : "s") · the top one is being worked"
    }
}

private struct PlanRowView: View {
    let row: PlanRow
    let model: ProjectWindowModel
    let isExpanded: Bool
    let reason: String?
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) { head }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title ?? "No milestone"), \(row.tasks.count) open issues")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.tasks) { task in issueRow(task) }
                    if row.tasks.isEmpty {
                        Text("No open issues.").font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk).padding(.vertical, 8)
                    }
                }
                .padding(.leading, 40).padding(.trailing, 14).padding(.vertical, 4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(DeskColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(row.isWorkingNow ? DeskColor.accent : DeskColor.divider, lineWidth: row.isWorkingNow ? 1.5 : 1))
    }

    private var head: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeskColor.faintInk)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title ?? "No milestone").font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                Text(subtitle).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk).lineLimit(1)
            }
            Spacer(minLength: 12)
            if row.title != nil { progress.frame(width: 150) }
            HStack(spacing: 4) {
                ForEach(row.priorityCounts, id: \.priority) { entry in
                    PropertyChip("\(entry.count) \(entry.priority)", tone: TaskFilterBar.tone(entry.priority),
                                 verticalPadding: 0, horizontalPadding: 6)
                }
            }
            .frame(minWidth: 120, alignment: .trailing)
            trailing.frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if row.title == nil { return "Open issues filed in no milestone" }
        if let reason { return "Working now · \(reason)" }
        return "\(row.tasks.count) open"
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DeskColor.divider)
                    Capsule().fill(DeskColor.tone(.running).dot)
                        .frame(width: proxy.size.width * CGFloat(row.closed) / CGFloat(max(row.total, 1)))
                }
            }
            .frame(height: 5)
            Text("\(row.closed) of \(row.total) done").font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk)
        }
    }

    @ViewBuilder private var trailing: some View {
        if row.isWorkingNow {
            StatusPill(badge: StatusBadge(.info, "Working now"))
        } else if let title = row.title {
            Button("Move to top") { Task { await model.moveToTopOfPlan(title) } }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .help("Make \(title) the milestone being worked — Next up on the Board reads it. Stored on this Mac, not on GitHub.")
        }
    }

    private func issueRow(_ task: DeskTask) -> some View {
        Button { model.openTask(task.id) } label: {
            HStack(spacing: 8) {
                Text(task.issueLabel).font(DeskFont.mono(11)).foregroundStyle(DeskColor.mutedInk).frame(width: 44, alignment: .leading)
                if let priority = task.priority {
                    PropertyChip(priority, tone: TaskFilterBar.tone(priority), verticalPadding: 0, horizontalPadding: 5)
                }
                Text(task.title).font(DeskFont.body).foregroundStyle(DeskColor.ink).lineLimit(1)
                ForEach(task.tags, id: \.self) { PropertyChip($0, verticalPadding: 0, horizontalPadding: 5) }
                Spacer(minLength: 8)
                Text(task.cardNote ?? task.column.title).font(.system(size: 11)).foregroundStyle(DeskColor.mutedInk).lineLimit(1)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(task.issueLabel)")
    }
}
