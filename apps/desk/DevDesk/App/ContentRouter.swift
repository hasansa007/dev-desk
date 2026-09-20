import DeskCore
import SwiftUI

struct ContentRouter: View {
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
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
            if let offBase = model.snapshot?.folderOffBase {
                NoticeBanner(tone: .waiting, title: "This folder is on \(offBase.branch == "HEAD" ? "a detached commit" : offBase.branch), not \(offBase.base)",
                             message: offBase.isDirty
                                ? "Work belongs in worktrees, one branch per task. It has uncommitted changes: Move to a worktree carries them to \(offBase.branch)'s own worktree and puts this folder back on \(offBase.base)."
                                : "Work belongs in worktrees, one branch per task, and this folder stays on \(offBase.base) — it is what Findings, the board and every new worktree read.") {
                    if offBase.canMoveToWorktree {
                        Button("Move to a worktree") { Task { await model.moveFolderBranchToWorktree(worktreeLocation: worktreeLocation) } }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                            .disabled(model.isWritingTracker)
                    }
                    Button("Switch back to \(offBase.base)") { Task { await model.switchFolderToBase() } }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        .disabled(model.isWritingTracker || offBase.isDirty)
                        .help(offBase.isDirty ? "Commit or move the uncommitted changes first" : "git switch \(offBase.base)")
                }
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
                    // The dock is the bottom edge of the work it came from (ADR 0021), holding several of this
                    // project's sessions at once. Never on Sessions: that tab is the same sessions full size,
                    // and one terminal cannot be hosted by two surfaces (ADR 0026).
                    if model.destination != .terminals, case .loaded = model.loadState {
                        SessionDock(model: model)
                    }
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
        case .board, .roadmap:   // Plan and Board are one tab, Work (ADR 0046 decision 13)
            if model.mode == .parallel {
                ParallelScreen(model: model)
            } else {
                BoardScreen(model: model)
            }
        case .findings:
            FindingsScreen(model: model)
        case .ideation:
            IdeationScreen(model: model)
        case .diagrams:
            DiagramsScreen(model: model)
        }
    }
}
