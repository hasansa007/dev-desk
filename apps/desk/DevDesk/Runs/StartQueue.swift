import DeskCore
import SwiftUI

/// How many of the app's agent slots are free right now: the limit from Settings → Execution, minus what is
/// live across every window. The same count Auto measures itself against, so a manual Start and Auto cannot
/// disagree about whether the app is full.
@MainActor enum AgentSlots { static var free: Int { max(0, AgentLimit.current - LiveShells.shared.agentCount) } }

/// One window's queue drain (ADR 0035): the cards a person's Start parked in Queued while every agent slot
/// was busy, released in board order as slots free. It looks again after every board load and every agent
/// start or exit in any window, the way `AutoAgents` does. It does not read the project's Auto setting:
/// this queue is work a person explicitly pressed Start on, so it runs whether or not Auto is on.
@MainActor
final class StartQueueRunner {
    private let model: ProjectWindowModel
    private var isWatching = false
    /// Releases this runner has dispatched whose sessions are not yet live, by the moment they left. A door
    /// run counts towards `agentCount` only once the terminal pane starts its session, but `startTask` reloads
    /// the board first — so the pass that reload triggers would read the same slots as free and spend them
    /// again. Each id leaves this ledger when `sessions.activeTaskIDs` picks it up (the app-wide count carries
    /// it from there), or after `releaseExpiry` — a run whose pane was never opened must not hold a slot forever.
    private var releasedNotYetLive: [String: Date] = [:]
    private let releaseExpiry: TimeInterval = 60

    init(model: ProjectWindowModel) {
        self.model = model
    }

    /// Safe to call more than once.
    func watch() {
        guard !isWatching else { return }
        isWatching = true
        observe()
        evaluate()
    }

    /// A board load replaces the snapshot, and every agent start or exit changes the count. Observation
    /// reports a change once, before it lands, so the pass runs on the next turn and watching resumes.
    private func observe() {
        withObservationTracking {
            _ = model.tasks
            _ = LiveShells.shared.agentCount
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observe()
                self.evaluate()
            }
        }
    }

    func evaluate() {
        guard case .local = model.ref, !SnapshotMode.shared.isActive else { return }
        let running = Set(model.sessions.activeTaskIDs)
        // Settle the ledger before spending: a release now live is counted by `agentCount` from here on,
        // and one past the expiry has forfeited its hold.
        let now = Date()
        releasedNotYetLive = releasedNotYetLive.filter { id, releasedAt in
            !running.contains(id) && now.timeIntervalSince(releasedAt) < releaseExpiry
        }
        let fallback = UserDefaults.standard.string(forKey: PreferenceKey.defaultConnection) ?? AgentDefaults.connection
        let store = model.launchStore
        let released = StartQueue.tasksToRelease(board: model.tasks,
                                                 freeSlots: StartQueue.spendableSlots(appFree: AgentSlots.free,
                                                                                      releasedNotYetLive: releasedNotYetLive.count),
                                                 runningTaskIDs: running)
            .compactMap(model.task)
            // The launch this card was parked with (ADR 0036). Without it the preferences AT RELEASE decided
            // what ran, so a card queued under Codex in Delegate started under whatever was current when a
            // slot freed. nil only for a card parked before this existed, which falls back to today's values.
            .map { task in (task: task, launch: DoorRuns.id(for: task).flatMap { store?.read(id: $0) }) }
            // A card that cannot start stays in Queued rather than being retried in a loop.
            .filter { model.startBlockedReason(for: $0.task, agent: connection(for: $0.launch, fallback: fallback)) == nil }
        // startTask records In progress when it dispatches, so a released card leaves Queued on its own
        // and the next pass sees a shorter queue — nothing extra to record here.
        for (task, launch) in released {
            releasedNotYetLive[task.id] = now
            model.startTask(task, agent: connection(for: launch, fallback: fallback), using: launch)
        }
    }

    /// The parked launch's agent, or the app default for a card parked before launches were stored.
    private func connection(for launch: TaskLaunch?, fallback: String) -> String {
        launch.map { AgentLaunch.connectionName($0.agent) } ?? fallback
    }
}

/// Starts the window's queue drain, and runs it again when the app's limit changes — a raised limit is a
/// freed slot the observation over `agentCount` would not see.
struct StartQueueHook: View {
    let queue: StartQueueRunner
    @AppStorage(PreferenceKey.agentLimit) private var limit = AgentLimit.defaultValue

    var body: some View {
        Color.clear
            .onAppear { queue.watch() }
            .onChange(of: limit) { queue.evaluate() }
    }
}
