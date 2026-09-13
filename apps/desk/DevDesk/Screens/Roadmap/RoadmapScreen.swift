import DeskCore
import SwiftUI

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
                if roadmap.themes.isEmpty && roadmap.milestones.isEmpty {
                    EmptyStateView(title: isRoadmapRunning ? "The roadmap door is running" : "No roadmap yet",
                                   message: isRoadmapRunning
                                       ? "It is reading this repository's recorded gaps now. Themes appear here once it files, and it asks before it does."
                                       : "The roadmap door reads what this repository already records about its own gaps and proposes milestones with epic parents underneath. Nothing here is invented, and it asks before it files.") {
                        DoorRunControl(model: model, door: "roadmap", title: "Run roadmap")
                    }
                } else {
                    RoadmapContent(roadmap: roadmap, model: model)
                }
            }
        }
    }
}

private struct RoadmapContent: View {
    let roadmap: Roadmap
    let model: ProjectWindowModel

    @State private var showsNote = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3)

    private var itemCount: Int { roadmap.themes.reduce(0) { $0 + $1.items.count } }

    private var summary: String {
        let themes = roadmap.themes.count
        return "\(itemCount) item\(itemCount == 1 ? "" : "s") across \(themes) theme\(themes == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
    }

    /// The same bar the board carries, in the same place, with the paragraph behind the same info button.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Roadmap")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Text(summary)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
            noteButton
            Spacer(minLength: 0)
            DoorRunControl(model: model, door: "roadmap", title: "Run roadmap", size: .small)
        }
        .screenHeaderBar()
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
        .help("Where these themes come from")
        .accessibilityLabel("Where these themes come from")
        .popover(isPresented: $showsNote) {
            Text(roadmap.note)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320)
                .padding(14)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(roadmap.themes) { theme in
                        ThemeColumn(theme: theme, model: model)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }

                if !roadmap.milestones.isEmpty {
                    SectionLabel("Milestones").padding(.top, 20)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(roadmap.milestones) { milestone in
                            MilestoneCard(milestone: milestone)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 18, trailing: 16))
            .pullToRefresh(isRefreshing: model.isRefreshing) { await model.load() }
        }
        .pullToRefreshSpace()
    }
}

private struct ThemeColumn: View {
    let theme: RoadmapTheme
    let model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon, title, count — the shape a board column's header already has. One line at one height: a
            // theme whose title wrapped made its own column start a row lower than the two beside it.
            HStack(spacing: 6) {
                Image(systemName: theme.icon)
                    .imageScale(.small)
                    .foregroundStyle(theme.isCritical ? DeskColor.tone(.failed).foreground : DeskColor.mutedInk)
                SectionLabel(theme.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(theme.items.count)")
                    .font(DeskFont.label)
                    .tracking(0.66)
                    .foregroundStyle(DeskColor.disabledDot)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .frame(height: DeskMetric.columnHeaderHeight)
            .help(theme.title)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(theme.items) { item in
                    RoadmapItemCard(item: item, model: model)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RoadmapItemCard: View {
    let item: RoadmapItem
    let model: ProjectWindowModel

    /// The same issue, as the board sees it. A roadmap row is the upcoming end of the board, so it shows what
    /// the card shows and offers what the card offers, rather than being a report you read and leave.
    private var task: DeskTask? {
        guard let number = Int(item.id) else { return nil }
        return model.tasks.first { $0.issueNumber == number }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(item.isCritical ? DeskColor.tone(.failed).foreground : DeskColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                action
            }
            FlowLayout(spacing: 6) {
                PropertyChip(item.workType, tone: workTypeTone, fill: chipFill(for: workTypeTone))
                PropertyChip(item.priority, fill: DeskColor.neutralChipFill2)
                PropertyChip(item.commitment.rawValue, tone: item.commitment == .committed ? .running : .waiting)
                if let task, task.issueNumber != nil {
                    PropertyChip("impact \(task.impact ?? "—")", fill: DeskColor.neutralChipFill2)
                    PropertyChip("complexity \(task.complexity ?? "—")", fill: DeskColor.neutralChipFill2)
                }
            }
            .padding(.top, 8)
            if let linkText = item.linkText {
                MarkdownText(linkText, font: .system(size: 12), color: DeskColor.secondaryInk)
                    .padding(.top, 9)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(item.isCritical ? DeskColor.tone(.failed).border : DeskColor.border))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        // A card opens its dialog, here as on the board (ADR 0021). Tap, not Button: the Open control is a
        // child, and an outer Button would eat its click — the mistake TaskCard records.
        .onTapGesture { if let task { model.openTaskHere(task.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { if let task { model.openTaskHere(task.id) } }
    }

    /// Open, not Build. "Build" ran `/dev` straight from a one-line summary — the roadmap is where you read
    /// what a thing is before deciding it should happen, so the button opens the issue's own page (ADR 0021's
    /// one dialog: goal, acceptance criteria, scope, description) and the decision is taken there, where its
    /// footer offers Start.
    @ViewBuilder private var action: some View {
        if let task {
            if let activity = model.activity(of: task) {
                Button { model.openTaskHere(task.id) } label: {
                    StatusPill(badge: StatusBadge(.running, activity.label, pulses: true))
                }
                .buttonStyle(.plain)
                .help("Open this task — it is running")
            } else {
                Button("Open") { model.openTaskHere(task.id) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Read the goal, acceptance criteria and description, and start it from there")
            }
        }
    }

    /// D:605–629: neutral chips use the lighter fill, and the Defect chip the stronger red fill.
    private func chipFill(for tone: StatusTone) -> Color? {
        switch tone {
        case .neutral: return DeskColor.neutralChipFill2
        case .failed: return DeskColor.diffDeleteFill
        default: return nil
        }
    }

    private var workTypeTone: StatusTone {
        switch item.workType {
        case "Epic": return .info
        case "Defect": return .failed
        default: return .neutral
        }
    }
}

private struct MilestoneCard: View {
    let milestone: Milestone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(milestone.title).font(DeskFont.body.weight(.semibold))
            ProgressTrack(progress: milestone.progress)
            Text(milestone.note).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 12)
    }
}

private struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(DeskColor.neutralChipFill)
                RoundedRectangle(cornerRadius: 3).fill(DeskColor.accent)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

struct RoadmapScreen_Previews: PreviewProvider {
    static var previews: some View {
        RoadmapPreviewHost()
            .frame(width: 1100, height: 780)
    }

    private struct RoadmapPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            RoadmapScreen(model: model)
                .task { await model.load() }
        }
    }
}
