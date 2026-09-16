import DeskCore
import SwiftUI

/// One window's Auto loop. For a local project with Auto on, it starts an agent for each queued task the scheduler picks, up to the
/// app-wide limit. It looks again after every board load, every agent start or exit in any window, and when Auto, the limit or the
/// worktree location changes.
@MainActor
final class AutoAgents {
    /// "<project id>|<task id>" for each task Auto has started in this app session, in any window, so none is started twice.
    private static var alreadyStarted: Set<String> = []
    /// The ones of those refused at the project root, which never ran; a new worktree location makes them eligible again.
    private static var refusedAtRoot: Set<String> = []

    private let model: ProjectWindowModel
    private let terminals: ShellTerminalRegistry
    private var isWatching = false
    /// Set while a pass's starts are preparing their folders; a pass asked for meanwhile runs once they are done.
    private var inFlight = false
    private var needsAnotherPass = false
    private var locationSettling: Task<Void, Never>?

    init(model: ProjectWindowModel, agents terminals: ShellTerminalRegistry) {
        self.model = model
        self.terminals = terminals
    }

    /// The warning under the setting, and the confirmation before it turns on.
    static func notice(limit: Int) -> String {
        "Auto runs up to \(limit == 1 ? "1 agent" : "\(limit) agents") in parallel. Each one spends tokens on your Claude or Codex plan, "
            + "and Dev Desk can't see your usage or prices. To keep spend down it runs at most \(limit) at a time, queues the rest, "
            + "and skips tasks that already have an agent running, including ones waiting on your answer."
    }

    /// Safe to call more than once.
    func watch() {
        guard !isWatching else { return }
        isWatching = true
        observe()
        evaluate()
    }

    /// A board load replaces the snapshot, and every agent start or exit changes the count. Observation reports a change once, before
    /// it lands, so the pass runs on the next turn and watching resumes. This works whether or not the window is on screen.
    private func observe() {
        withObservationTracking {
            _ = model.tasks
            _ = LiveShells.shared.agentCount
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.terminals.isClosed else { return }
                self.observe()
                self.evaluate()
            }
        }
    }

    func evaluate() {
        guard case .local = model.ref, !terminals.isClosed, !SnapshotMode.shared.isActive, isOn else { return }
        guard !inFlight else {
            needsAnotherPass = true
            return
        }
        guard case .ready(let agent) = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? []) else { return }
        let board = model.tasks
        let started = Set(board.map(\.id).filter { Self.alreadyStarted.contains(key($0)) })
        // Active takes in a start still preparing its folder, so a task is never started twice.
        let picked = AutoScheduler.tasksToStart(board: board, runningAgentTaskIDs: Set(model.sessions.activeTaskIDs),
                                                alreadyStarted: started, runningAgentsAcrossApp: LiveShells.shared.agentCount,
                                                limit: AgentLimit.current).compactMap(model.task)
        guard !picked.isEmpty else { return }
        let location = UserDefaults.standard.string(forKey: PreferenceKey.worktreeLocation) ?? AgentDefaults.worktreeLocation
        inFlight = true
        // Auto's starts refuse the project root, and launch nothing if Auto is turned off before the folder is ready.
        let starts = picked.map { task in
            Self.alreadyStarted.insert(key(task.id))
            return (key(task.id), terminals.startAgent(for: task, agent: agent, worktreeLocation: location,
                                                    mode: RunModeChoice.current(for: model.ref), refusingRoot: true,
                                                    stillWanted: { [weak self] in self?.isOn ?? false }))
        }
        Task {
            for (key, start) in starts {
                switch await start.value {
                // It stays in alreadyStarted, so Auto doesn't retry it in a loop, until the worktree location changes.
                case .refusedAtRoot: Self.refusedAtRoot.insert(key)
                // It never ran, so turning Auto on again may start it.
                case .cancelled: Self.alreadyStarted.remove(key)
                case .launched, .skipped: break
                }
            }
            inFlight = false
            if needsAnotherPass {
                needsAnotherPass = false
                evaluate()
            }
        }
    }

    /// The tasks refused at the project root may have a folder of their own at the new location. The field changes with every keystroke,
    /// and a half-typed path can itself be a usable location, so they're tried again only once the value has settled for 2 s.
    func worktreeLocationChanged() {
        locationSettling?.cancel()
        locationSettling = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            Self.alreadyStarted.subtract(Self.refusedAtRoot)
            Self.refusedAtRoot.removeAll()
            evaluate()
        }
    }

    private var isOn: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.autoMode(model.ref)) }

    private func key(_ taskID: String) -> String { "\(model.ref.id)|\(taskID)" }
}

/// Starts the window's Auto loop, and runs it again when this project's Auto setting, the app's limit or the worktree location changes.
struct AutoAgentsHook: View {
    let auto: AutoAgents
    @AppStorage private var autoMode: Bool
    @AppStorage(PreferenceKey.agentLimit) private var limit = AgentLimit.defaultValue
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation

    init(auto: AutoAgents, ref: ProjectRef) {
        self.auto = auto
        _autoMode = AppStorage(wrappedValue: false, PreferenceKey.autoMode(ref))
    }

    var body: some View {
        Color.clear
            .onAppear { auto.watch() }
            .onChange(of: autoMode) { auto.evaluate() }
            .onChange(of: limit) { auto.evaluate() }
            .onChange(of: worktreeLocation) { auto.worktreeLocationChanged() }
    }
}
