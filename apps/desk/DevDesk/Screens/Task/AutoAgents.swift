import DeskCore
import SwiftUI

/// One window's Auto loop. For a local project with Auto on, it starts an agent for each queued task the scheduler picks, up to the
/// app-wide limit. It looks again after every board load, every agent start or exit in any window, and when Auto or the limit changes.
@MainActor
final class AutoAgents {
    /// "<project id>|<task id>" for each task Auto has started in this app session, in any window, so none is started twice.
    private static var alreadyStarted: Set<String> = []

    private let model: ProjectWindowModel
    private let agents: ShellTerminalRegistry
    private var isWatching = false
    /// Set while a pass's starts are preparing their folders; a pass asked for meanwhile runs once they are done.
    private var inFlight = false
    private var needsAnotherPass = false

    init(model: ProjectWindowModel, agents: ShellTerminalRegistry) {
        self.model = model
        self.agents = agents
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
                guard let self, !self.agents.isClosed else { return }
                self.observe()
                self.evaluate()
            }
        }
    }

    func evaluate() {
        guard case .local = model.ref, !agents.isClosed, !SnapshotMode.shared.isActive,
              UserDefaults.standard.bool(forKey: PreferenceKey.autoMode(model.ref)) else { return }
        guard !inFlight else {
            needsAnotherPass = true
            return
        }
        guard case .ready(let agent) = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? []) else { return }
        let board = model.tasks
        let started = Set(board.map(\.id).filter { Self.alreadyStarted.contains(key($0)) })
        // Active takes in a start still preparing its folder, so a task is never started twice.
        let picked = AutoScheduler.tasksToStart(board: board, runningAgentTaskIDs: Set(model.agentSessions.activeTaskIDs),
                                                alreadyStarted: started, runningAgentsAcrossApp: LiveShells.shared.agentCount,
                                                limit: AgentLimit.current).compactMap(model.task)
        guard !picked.isEmpty else { return }
        let location = UserDefaults.standard.string(forKey: PreferenceKey.worktreeLocation) ?? "~/.devdesk/wt"
        inFlight = true
        // A start refused at the project root stays in alreadyStarted, so Auto never retries it in a loop.
        let starts = picked.map { task in
            Self.alreadyStarted.insert(key(task.id))
            return agents.startAgent(for: task, agent: agent, worktreeLocation: location, refusingRoot: true)
        }
        Task {
            for start in starts { await start.value }
            inFlight = false
            if needsAnotherPass {
                needsAnotherPass = false
                evaluate()
            }
        }
    }

    private func key(_ taskID: String) -> String { "\(model.ref.id)|\(taskID)" }
}

/// Starts the window's Auto loop, and runs it again when this project's Auto setting or the app's limit changes.
struct AutoAgentsHook: View {
    let auto: AutoAgents
    @AppStorage private var autoMode: Bool
    @AppStorage(PreferenceKey.agentLimit) private var limit = AgentLimit.defaultValue

    init(auto: AutoAgents, ref: ProjectRef) {
        self.auto = auto
        _autoMode = AppStorage(wrappedValue: false, PreferenceKey.autoMode(ref))
    }

    var body: some View {
        Color.clear
            .onAppear { auto.watch() }
            .onChange(of: autoMode) { auto.evaluate() }
            .onChange(of: limit) { auto.evaluate() }
    }
}
