import DeskCore
import SwiftUI

struct ContentRouter: View {
    @Bindable var model: ProjectWindowModel
    @Environment(\.deskWindowSize) private var window
    /// The viewer filling the window is a way of looking at one file, not a state of the project: it belongs
    /// to this host and ends with it.
    @State private var fileViewerExpanded = false

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

                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                if showsSplitViewer {
                    Rectangle().fill(DeskColor.border).frame(width: 1)
                    viewer.frame(width: viewerWidth)
                }
                if model.filesOpen {
                    EdgeResizer(edge: .trailing, size: $model.filesWidth, range: DeskMetric.filesWidthRange)
                    FilesPanel(model: model)
                        // A 420 pt panel on a 920 pt window leaves the board a strip: the edge yields first.
                        .frame(width: filesColumnWidth)
                }
            }
            .overlay { if showsFloatingViewer { floatingViewer } }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(DeskColor.canvas)
        // Filling the window is about the file you were reading; with none open there is nothing to fill it with.
        .onChange(of: model.selectedFilePath) { _, path in if path == nil { fileViewerExpanded = false } }
    }

    // MARK: - The selected file's pane

    private var filesColumnWidth: CGFloat {
        min(model.filesWidth, max(window.width * 0.45, DeskMetric.filesWidthRange.lowerBound))
    }

    /// A third of the window, and never so narrow that a line of code has nowhere to go.
    private var viewerWidth: CGFloat { max(360, window.width * 0.33) }

    /// A file earns a column of its own only while the work keeps a third of the window after the tree and the
    /// viewer have taken theirs — with both at their floors that is a window of about 926 pt. Below it, three
    /// columns are three strips, so the viewer floats over the work rather than squeezing it.
    private var fitsBesideContent: Bool {
        window.width - (model.filesOpen ? filesColumnWidth : 0) - viewerWidth >= window.width * 0.33
    }

    private var hasSelectedFile: Bool { model.selectedFilePath != nil && model.projectRoot != nil }
    private var showsSplitViewer: Bool { hasSelectedFile && !fileViewerExpanded && fitsBesideContent }
    private var showsFloatingViewer: Bool { hasSelectedFile && (fileViewerExpanded || !fitsBesideContent) }

    @ViewBuilder private var viewer: some View {
        if let path = model.selectedFilePath, let root = model.projectRoot {
            FileViewerPane(model: model, path: path, url: model.selectedFileURL, root: root,
                           isExpanded: $fileViewerExpanded)
        }
    }

    /// Over the window rather than inside it: the scrim keeps the work visible behind the file, and dismisses it.
    private var floatingViewer: some View {
        ZStack(alignment: .leading) {
            DeskColor.ink.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { model.closeFile() }
            viewer
                .frame(maxWidth: fileViewerExpanded ? .infinity : max(360, window.width * 0.82), maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.border).frame(width: 1) }
        }
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
