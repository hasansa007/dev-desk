import AppKit
import DeskCore
import SwiftUI

/// `-DevDeskSnapshot <dir>` opens one project window, writes a PNG of each state in a fixed list, then quits.
@MainActor
@Observable
final class SnapshotMode {
    static let shared = SnapshotMode()

    let directory: URL?
    let ref: ProjectRef
    private(set) var colorScheme: ColorScheme?
    @ObservationIgnored private var started = false

    private init() {
        let defaults = UserDefaults.standard
        directory = defaults.string(forKey: "DevDeskSnapshot").map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        ref = defaults.string(forKey: "DevDeskSnapshotProject").flatMap(Self.ref(from:)) ?? .sample(.studyHub)
        colorScheme = directory == nil ? nil : .light
    }

    var isActive: Bool { directory != nil }

    /// Parses `sample:<project>` or `local:<absolute path>`, the same form as `ProjectRef.id`.
    static func ref(from id: String) -> ProjectRef? {
        if id.hasPrefix("sample:") { return SampleProject(rawValue: String(id.dropFirst(7))).map(ProjectRef.sample) }
        if id.hasPrefix("local:") { return .local(path: String(id.dropFirst(6))) }
        return nil
    }

    func run(window: NSWindow, model: ProjectWindowModel) {
        guard let directory, !started else { return }
        started = true
        Task {
            await capture(window: window, model: model, into: directory)
            NSApp.terminate(nil)
        }
    }

    private func capture(window: NSWindow, model: ProjectWindowModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        window.setFrame(NSRect(x: visible.minX + 40, y: visible.maxY - 960, width: 1440, height: 920), display: true)
        window.makeKeyAndOrderFront(nil)
        guard await waitForLoad(model) else {
            write(window.contentView, to: directory.appendingPathComponent("00-load-failed.png"))
            return
        }
        for state in model.ref.isSample ? Self.sampleStates : Self.localStates {
            reset(model)
            colorScheme = state.isDark ? .dark : .light
            state.apply(model)
            try? await Task.sleep(for: .milliseconds(600))
            let view = state.isSheet ? window.attachedSheet?.contentView : window.contentView
            write(view, to: directory.appendingPathComponent("\(state.name).png"))
            if state.isSheet {
                model.dismissSheet()
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func waitForLoad(_ model: ProjectWindowModel) async -> Bool {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            switch model.loadState {
            case .loaded: return true
            case .failed: return false
            case .loading: try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return false
    }

    private func reset(_ model: ProjectWindowModel) {
        model.sheet = nil
        model.insightsOpen = false
        model.insightsDocked = false
        model.runsOpen = false
        model.runsDocked = false
        model.filesOpen = false
        model.mode = .focus
        model.showBacklog = false
        model.searchText = ""
        model.dockOpen = true
        model.dockPlacement = .bottom
        model.dockSplit = false
        model.decisionsTab = .needsAttention
    }

    private func write(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private struct Capture {
        let name: String
        var isSheet = false
        var isDark = false
        let apply: @MainActor (ProjectWindowModel) -> Void
    }

    private static let sampleStates: [Capture] = [
        Capture(name: "01-task42-dialog", isSheet: true) { $0.openTask("42") },
        Capture(name: "02-board") { $0.go(.board) },
        Capture(name: "03-board-backlog") { $0.go(.board); $0.showBacklog = true },
        Capture(name: "04-task42-overview", isSheet: true) { $0.openTask("42"); $0.tab = .requirements },
        Capture(name: "05-task42-changes", isSheet: true) { $0.openTask("42"); $0.tab = .changes },
        Capture(name: "06-task42-evidence", isSheet: true) { $0.openTask("42"); $0.tab = .evidence },
        Capture(name: "07-task42-dock-side-split") { $0.openTask("42"); $0.setDockPlacement(.side); $0.dockSplit = true },
        Capture(name: "08-task57-activity") { $0.openTask("57") },
        Capture(name: "09-task63-activity") { $0.openTask("63") },
        Capture(name: "10-parallel") { $0.setMode(.parallel) },
        Capture(name: "11-survey") { $0.go(.survey) },
        Capture(name: "12-reconcile-sheet", isSheet: true) { $0.go(.survey); $0.present(.reconcileFinding("F-108")) },
        Capture(name: "13-roadmap") { $0.go(.roadmap) },
        Capture(name: "14-decisions") { $0.go(.decisions) },
        Capture(name: "15-decisions-history") { $0.go(.decisions); $0.decisionsTab = .history },
        Capture(name: "16-settings-agents", isSheet: true) { $0.settingsSection = .agentsAndDefaults; $0.present(.settings) },
        Capture(name: "17-insights-docked") { $0.openTask("42"); $0.dockInsights() },
        Capture(name: "18-insights-floating") { $0.openTask("42"); $0.floatInsights() },
        Capture(name: "19-open-project-sheet", isSheet: true) { $0.go(.board); $0.present(.openProject) },
        Capture(name: "20-compare-sheet", isSheet: true) { $0.openTask("42"); $0.present(.compareOutputs) },
        Capture(name: "21-followup-sheet", isSheet: true) { $0.openTask("42"); $0.present(.followUp) },
        Capture(name: "22-handoff-sheet", isSheet: true) { $0.openTask("63"); $0.present(.handoff) },
        Capture(name: "23-dark-task42", isDark: true) { $0.openTask("42"); $0.insightsOpen = true },
        // #65 is queued with no branch, so opening it presents the sheet rather than a workspace.
        Capture(name: "24-unstarted-task-sheet", isSheet: true) { $0.go(.board); $0.openTask("65") },
        Capture(name: "25-cancel-task-sheet", isSheet: true) { $0.go(.board); $0.present(.cancelTask("65")) },
    ]

    private static let localStates: [Capture] = [
        Capture(name: "01-board") { $0.go(.board) },
        Capture(name: "02-first-task-changes") { model in
            if let id = firstTaskID(model) { model.openTask(id) }
            model.tab = .changes
        },
        Capture(name: "03-survey") { $0.go(.survey) },
        Capture(name: "04-roadmap") { $0.go(.roadmap) },
        Capture(name: "05-decisions") { $0.go(.decisions) },
        Capture(name: "06-settings-connections", isSheet: true) { $0.settingsSection = .accountsAndConnections; $0.present(.settings) },
        // Idle, so the capture shows the trust note and the planned folder; nothing is started.
        Capture(name: "07-first-task-shell") { model in
            if let id = firstTaskID(model) { model.openTask(id) }
            model.dockTabID = model.selectedTask?.dock?.tabs.first { $0.kind == .liveShell }?.id
        },
        // Idle, so the capture shows the run with the command it would type; nothing is started.
        Capture(name: "08-runs-panel") { model in
            model.go(.survey)
            model.prepareRun(door: "survey", title: "Survey", agent: "Claude")
            model.floatRuns()
        },
        Capture(name: "09-unstarted-task-sheet", isSheet: true) { model in
            if let id = firstUnstartedTaskID(model) { model.openTask(id) }
        },
        Capture(name: "10-ideation") { $0.go(.ideation) },
        // Rated cards sit in Backlog, which the board hides until asked.
        Capture(name: "11-board-backlog") { $0.go(.board); $0.showBacklog = true },
        Capture(name: "12-files") { $0.go(.board); $0.selectedFilePath = "README.md"; $0.dockFiles() },
        Capture(name: "13-run-focus", isSheet: true) { $0.go(.ideation); $0.present(.runFocus("ideation")) },
        Capture(name: "14-task-dialog", isSheet: true) { model in
            if let id = firstUnstartedTaskID(model) { model.openTask(id) }
        },
    ]

    /// The first card nobody has started, so the sheet capture shows Start task against a real folder.
    private static func firstUnstartedTaskID(_ model: ProjectWindowModel) -> String? {
        model.tasks.first { $0.isUnstarted }?.id
    }

    /// The first in-progress card, so the Changes capture shows a real diff when one exists; else the first card on the board.
    private static func firstTaskID(_ model: ProjectWindowModel) -> String? {
        let order = BoardColumn.allCases.filter { $0 != .backlog }
        let visible = order.flatMap { column in model.tasks.filter { $0.column == column } }
        return (visible.first { $0.column == .inProgress } ?? visible.first)?.id
    }
}

/// Attached to the snapshot target's window; does nothing outside snapshot mode.
struct SnapshotWindowHook: View {
    let ref: ProjectRef
    let model: ProjectWindowModel

    var body: some View {
        if SnapshotMode.shared.isActive && SnapshotMode.shared.ref == ref {
            WindowAccessor { SnapshotMode.shared.run(window: $0, model: model) }
        }
    }
}

/// In snapshot mode the launcher window opens the project window and closes itself.
struct SnapshotBootstrap: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content.onAppear {
            guard SnapshotMode.shared.isActive else { return }
            openWindow(value: SnapshotMode.shared.ref)
            dismissWindow(id: "launcher")
        }
    }
}

/// Reports the hosting `NSWindow`; `NSApp.keyWindow` is unreliable when the app is launched from a terminal.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReportingView { WindowReportingView(onWindow: onWindow) }
    func updateNSView(_ nsView: WindowReportingView, context: Context) {}
}

final class WindowReportingView: NSView {
    private let onWindow: (NSWindow) -> Void

    init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow(window) }
    }
}
