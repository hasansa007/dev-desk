import DeskCore
import SwiftUI

struct ContentRouter: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            if let reloadError = model.reloadError {
                NoticeBanner(tone: .failed, title: "Reload failed", message: Markdown.escape(reloadError))
                    .padding([.horizontal, .top], 12)
            }
            if let failure = model.writeFailure {
                NoticeBanner(tone: .failed, title: failure.title, message: failure.message) {
                    Button("Dismiss") { model.dismissWriteFailure() }
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
                        EdgeResizer(edge: .bottom, size: $model.runsHeight, range: DeskMetric.runsHeightRange)
                        RunsPanel(model: model)
                            .frame(height: model.runsHeight)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if model.filesOpen {
                    EdgeResizer(edge: .trailing, size: $model.filesWidth, range: DeskMetric.filesWidthRange)
                    FilesPanel(model: model)
                        .frame(width: model.filesWidth)
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
            // A load error can quote the project's folder path, which is often the repository's own name.
            EmptyStateView(title: "This project could not be opened", message: Markdown.escape(message)) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(DeskButtonStyle(kind: .primary))
            }
        case .loaded:
            destination
        }
    }

    @ViewBuilder private var destination: some View {
        switch model.destination {
        case .terminals:
            TerminalsScreen(model: model)
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
