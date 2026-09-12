import DeskCore
import SwiftUI

struct ContentRouter: View {
    let model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            if let reloadError = model.reloadError {
                NoticeBanner(tone: .failed, title: "Reload failed", message: reloadError)
                    .padding([.horizontal, .top], 12)
            }
            if let trackerError = model.trackerError {
                NoticeBanner(tone: .failed, title: "The tracker was not changed", message: trackerError) {
                    Button("Dismiss") { model.dismissTrackerError() }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                }
                .padding([.horizontal, .top], 12)
            }
            HStack(spacing: 0) {
                content
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if model.insightsOpen && model.insightsDocked {
                    InsightsPanel(model: model, placement: .docked)
                        .frame(width: DeskMetric.insightsDockedWidth)
                }
                if model.runsOpen && model.runsDocked {
                    RunsPanel(model: model, placement: .docked)
                        .frame(width: DeskMetric.runsDockedWidth)
                }
                if model.filesOpen && model.filesDocked {
                    FilesPanel(model: model, placement: .docked)
                        .frame(width: DeskMetric.filesDockedWidth)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(DeskColor.canvas)
        .overlay(alignment: .bottomTrailing) {
            if model.insightsOpen && !model.insightsDocked {
                InsightsPanel(model: model, placement: .floating)
                    .frame(width: DeskMetric.insightsFloatingSize.width, height: DeskMetric.insightsFloatingSize.height)
                    .padding(.trailing, 36)
                    .padding(.bottom, 34)
            }
        }
        // Trailing centre: a floating Files panel clears the two that sit in the bottom corners.
        .overlay(alignment: .trailing) {
            if model.filesOpen && !model.filesDocked {
                FilesPanel(model: model, placement: .floating)
                    .frame(width: DeskMetric.filesFloatingSize.width, height: DeskMetric.filesFloatingSize.height)
                    .padding(.trailing, 28)
            }
        }
        // Bottom leading, so a floating Runs panel and a floating Insights panel never cover each other.
        .overlay(alignment: .bottomLeading) {
            if model.runsOpen && !model.runsDocked {
                RunsPanel(model: model, placement: .floating)
                    .frame(width: DeskMetric.runsFloatingSize.width, height: DeskMetric.runsFloatingSize.height)
                    .padding(.leading, 24)
                    .padding(.bottom, 34)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            EmptyStateView(title: "This project could not be opened", message: message) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(DeskButtonStyle(kind: .primary))
            }
        case .loaded:
            destination
        }
    }

    @ViewBuilder private var destination: some View {
        switch model.destination {
        case .board:
            if model.mode == .parallel {
                ParallelScreen(model: model)
            } else if let task = model.selectedTask {
                TaskWorkspaceScreen(model: model, task: task)
            } else {
                BoardScreen(model: model)
            }
        case .roadmap:
            RoadmapScreen(model: model)
        case .reports:
            ReportsScreen(model: model)
        case .decisions:
            DecisionsScreen(model: model)
        case .settings:
            SettingsScreen(model: model)
        }
    }
}
