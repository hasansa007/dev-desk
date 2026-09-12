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
            // Two window edges, the way Xcode arranges the same two things: output along the bottom of the
            // work it came from, the file tree down the right of everything.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    content
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    if model.runsOpen {
                        RunsPanel(model: model)
                            .frame(height: DeskMetric.runsPanelHeight)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if model.filesOpen {
                    FilesPanel(model: model)
                        .frame(width: DeskMetric.filesPanelWidth)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(DeskColor.canvas)
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
            } else {
                BoardScreen(model: model)
            }
        case .roadmap:
            RoadmapScreen(model: model)
        case .survey:
            FindingsScreen(model: model)
        case .ideation:
            IdeationScreen(model: model)
        case .insights:
            InsightsScreen(model: model)
        }
    }
}
