import AppKit
import DeskCore
import SwiftUI

/// One project's whole working state — its model, its sessions, its Auto loop, its queue — owned by the
/// workspace rather than by a view (ADR 0050). It was `ProjectWindow`'s `@State`, which tied a project's life
/// to a window being open on it; the strip switches projects without closing anything, so a project that is
/// not on screen has to keep loading, keep running and keep reporting what needs you.
@MainActor
@Observable
final class ProjectContext: Identifiable {
    let ref: ProjectRef
    let model: ProjectWindowModel
    /// This project's sessions — one per task, shell or agent (ADR 0026); they end when the window closes or
    /// the project leaves the strip, never when you look at another project.
    let terminals: ShellTerminalRegistry
    let auto: AutoAgents
    /// Drains the cards a Start parked in Queued (ADR 0035); it runs whether or not Auto is on.
    let queue: StartQueueRunner
    /// Set by the workspace: only the project you are looking at can have a session already on screen, so only
    /// it may suppress a notification.
    var isFrontmost = false
    /// The split view's columns, per project — each project keeps its own focus.
    var columns: NavigationSplitViewVisibility = .all
    private var focusRestored = false

    var id: String { ref.id }

    init(ref: ProjectRef) {
        self.ref = ref
        let model = ProjectWindowModel(ref: ref, source: DataSources.make(for: ref))
        // The model decides when a file is opened; `NSWorkspace` is AppKit's, so the app target says how.
        model.editorOpen = { await FileOpen.inEditor($0) }
        self.model = model
        let terminals = ShellTerminalRegistry(sessions: model.sessions)
        self.terminals = terminals
        self.auto = AutoAgents(model: model, agents: terminals)
        self.queue = StartQueueRunner(model: model)
        wireSessionEvents()
    }

    // MARK: - What the strip shows

    /// Runs in this project waiting on an answer. The strip's amber number, and what Home counts as needing you.
    /// Only LIVE sessions count: `waitingSessions` is a record of what each agent last reported and nothing takes
    /// an id out of it when the session ends, so a project with nothing running wore an amber 1 for the last turn
    /// that ever ended there (2026-09-20, on screen, reported). The toolbar's summary already counted this way.
    var waitingCount: Int { model.waitingSessions.count { model.sessions.state(for: $0).isLive } }

    /// Anything live here at all — the strip's green dot.
    var isRunning: Bool { SessionRow.all(in: model).contains(where: \.isLive) }

    var name: String { model.snapshot?.project.name ?? ref.displayName }

    var displayPath: String { model.snapshot?.project.displayPath ?? "" }

    var branch: String { model.snapshot?.project.branch ?? "" }

    // MARK: - Sessions

    /// What each session reports. It was set in the window's `onAppear`, which meant a project you were not
    /// looking at reported nothing: its questions never reached the strip and its Done cards never closed.
    private func wireSessionEvents() {
        terminals.onEvent = { [weak self] id, event in
            guard let self, case .local(let path) = self.ref else { return }
            switch event {
            case .turnStarted: self.model.markSession(id, waiting: false)
            case .turnFinished, .question: self.model.markSession(id, waiting: true)
            case .exited: self.model.markSession(id, waiting: false)
            case .bell: break
            }
            if event == .turnFinished {
                // A turn is when an agent commits, opens a PR or merges; without auto-reload nothing else would show it,
                // and a task merged in that turn would never be seen reaching Done.
                if self.model.closingOnDone.contains(id) { self.closeDone() }
                Task { await self.model.sync() }
            }
            // On screen means this project is the one in front AND its Sessions tab has that session selected.
            let onScreen = NSApp.isActive && self.isFrontmost
                && self.model.destination == .terminals && self.model.selectedSessionID == id
            RunNotifications.post(event, session: id, name: self.model.sessionName(id), directory: path, isOnScreen: onScreen)
        }
    }

    /// Ends and takes off the list each session whose task just reached Done, except an agent still mid-turn: its
    /// turn's end calls this again.
    func closeDone() {
        for id in model.closingOnDone where !terminals.isMidTurn(id) {
            model.closingOnDone.remove(id)
            guard model.sessions.state(for: id).isLive else { continue }
            terminals.end(taskID: id)
            model.runs.remove(id)
        }
    }

    /// The project is leaving the strip: its sessions end with it, the way closing its window used to end them.
    func end() {
        terminals.endAll()
    }

    // MARK: - Each project keeps its own focus

    /// Was `@SceneStorage`, which is the WINDOW's memory: with every project in one window they overwrote each
    /// other's place, so switching projects landed you wherever the last one had been. Keyed by project now.
    private static func focusKey(_ ref: ProjectRef, _ part: String) -> String { "desk.focus.\(ref.id).\(part)" }

    /// Runs once, after whichever load succeeds first, so a Retry after a failed first load still restores and records.
    func applyFirstLoad() {
        guard !focusRestored else { return }
        focusRestored = true
        guard !SnapshotMode.shared.isActive else { return }
        restoreFocus()
        recordRecent()
    }

    /// An empty stored task id means the board was showing no task; an id that no longer exists is ignored.
    private func restoreFocus() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.focusKey(ref, "taskID")) {
            if stored.isEmpty {
                model.selectedTaskID = nil
            } else if model.task(stored) != nil {
                model.openTask(stored)
            }
        }
        if let raw = defaults.string(forKey: Self.focusKey(ref, "destination")), let value = Destination(rawValue: raw) {
            model.destination = value
        }
        if let raw = defaults.string(forKey: Self.focusKey(ref, "tab")), let value = TaskTab(rawValue: raw) {
            model.tab = value
        }
    }

    func rememberFocus() {
        guard focusRestored, !SnapshotMode.shared.isActive else { return }
        let defaults = UserDefaults.standard
        defaults.set(model.destination.rawValue, forKey: Self.focusKey(ref, "destination"))
        defaults.set(model.selectedTaskID ?? "", forKey: Self.focusKey(ref, "taskID"))
        defaults.set(model.tab.rawValue, forKey: Self.focusKey(ref, "tab"))
    }

    private func recordRecent() {
        guard case .local = ref, let project = model.snapshot?.project else { return }
        AppServices.recents.record(ref, name: project.name, displayPath: project.displayPath)
    }
}
