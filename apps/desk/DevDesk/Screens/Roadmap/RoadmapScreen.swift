import DeskCore
import SwiftUI

struct RoadmapScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let snapshot = model.snapshot {
            SurfaceView(snapshot.roadmap) { roadmap in
                if roadmap.themes.isEmpty && roadmap.milestones.isEmpty {
                    EmptyStateView(title: "No roadmap yet",
                                   message: "Run `/dev:roadmap` to turn recorded gaps into milestones and epics.")
                } else {
                    RoadmapContent(roadmap: roadmap)
                }
            }
        }
    }
}

private struct RoadmapContent: View {
    let roadmap: Roadmap

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Roadmap").font(DeskFont.section)
                    Text(roadmap.note).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(roadmap.themes) { theme in
                        ThemeColumn(theme: theme)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.top, 16)

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
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        }
    }
}

private struct ThemeColumn: View {
    let theme: RoadmapTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(theme.title)
            ForEach(theme.items) { item in
                RoadmapItemCard(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RoadmapItemCard: View {
    let item: RoadmapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(item.title)
                .font(DeskFont.body.weight(.semibold))
                .foregroundStyle(item.isCritical ? DeskColor.tone(.failed).foreground : DeskColor.ink)
            FlowLayout(spacing: 6) {
                PropertyChip(item.workType, tone: workTypeTone)
                PropertyChip(item.priority, tone: .neutral)
                PropertyChip(item.commitment.rawValue, tone: item.commitment == .committed ? .running : .waiting)
            }
            if let linkText = item.linkText {
                MarkdownText(linkText, font: .system(size: 12), color: DeskColor.secondaryInk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(item.isCritical ? DeskColor.tone(.failed).border : DeskColor.border))
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
