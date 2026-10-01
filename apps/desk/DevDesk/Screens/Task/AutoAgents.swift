import DeskCore
import SwiftUI

/// One window's Auto loop. For a local project with Auto on, it presses Start on Next up's cards, in Next up's order, up to the
/// app-wide limit. It looks again after every board load, every agent start or exit in any window, and when Auto or the limit changes.
///
/// It starts a card exactly as the card's own Start does — `model.startTask` — so an Auto start is a `/dev` run in Sessions that moves
/// the card to In progress. It used to open an interactive agent in a terminal of its own (ADR 0018), which a local card, having no
/// number, could never use: on a project with no tracker Auto started nothing at all (2026-10-01).
@MainActor
final class AutoAgents {
    /// "<project id>|<task id>" for each task Auto has started in this app session, in any window, so none is started twice.
    private static var alreadyStarted: Set<String> = []

    private let model: ProjectWindowModel
    private let terminals: ShellTerminalRegistry
    private var isWatching = false
    /// Starts dispatched whose sessions are not live yet — `StartQueueRunner`'s ledger, for the same reason: `startTask` reloads the
    /// board before the run's session counts towards the limit, and the pass that reload triggers must not spend the slot again.
    private var startedNotYetLive: [String: Date] = [:]
    private let startExpiry: TimeInterval = 60

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
        guard case .ready(let kind) = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? [],
                                                          terminalAgents: model.snapshot?.terminalAgents ?? []) else { return }
        let fallback = AgentLaunch.connectionName(kind)
        let tasks = model.tasks
        let live = Set(tasks.filter { model.activity(of: $0) != nil }.map(\.id))
        let now = Date()
        startedNotYetLive = startedNotYetLive.filter { id, startedAt in
            !live.contains(id) && now.timeIntervalSince(startedAt) < startExpiry
        }
        // Next up as the board shows it: the dragged order first, the automatic one filling in.
        let nextUp = model.nextUpOrder.apply(BoardOrder.inColumn(.readyForDev, tasks.filter { $0.column == .readyForDev }))
        let picked = AutoScheduler.tasksToStart(board: nextUp, runningAgentTaskIDs: live.union(startedNotYetLive.keys),
                                                alreadyStarted: Set(tasks.map(\.id).filter { Self.alreadyStarted.contains(key($0)) }),
                                                waiting: model.waitingTaskIDs,
                                                runningAgentsAcrossApp: LiveShells.shared.agentCount + startedNotYetLive.count,
                                                limit: AgentLimit.current)
            .compactMap(model.task)
        for task in picked {
            // What this card was last started with, as its own Start would run it; otherwise this project's agent now.
            let launch = model.rememberedLaunch(for: task)
            let agent = launch.map { AgentLaunch.connectionName($0.agent) } ?? fallback
            // Marked even when refused, so a card Start would refuse is skipped rather than retried on every pass.
            Self.alreadyStarted.insert(key(task.id))
            guard model.startBlockedReason(for: task, agent: agent) == nil else { continue }
            startedNotYetLive[task.id] = now
            model.startTask(task, agent: agent, using: launch)
        }
    }

    private var isOn: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.autoMode(model.ref)) }

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

/// This project's Auto switch, in Settings › Project overrides and in the board's header. Turning it on asks first, since it
/// spends tokens unattended; Cancel leaves it off. Turning it off never asks.
struct AutoSwitch: View {
    @AppStorage private var autoMode: Bool
    @AppStorage(PreferenceKey.agentLimit) private var agentLimit = AgentLimit.defaultValue
    @State private var confirming = false
    /// The board shows "Auto" beside the switch; Settings has the row's title for that.
    private let showsLabel: Bool

    init(ref: ProjectRef, showsLabel: Bool = false) {
        _autoMode = AppStorage(wrappedValue: false, PreferenceKey.autoMode(ref))
        self.showsLabel = showsLabel
    }

    static func notice(limit: Int) -> String {
        AutoAgents.notice(limit: min(max(limit, AgentLimit.range.lowerBound), AgentLimit.range.upperBound))
    }

    var body: some View {
        Toggle(isOn: Binding(get: { autoMode }, set: { isOn in
            if isOn { confirming = true } else { autoMode = false }
        })) {
            Text("Auto")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.ink)
        }
        .toggleStyle(.switch)
        .controlSize(showsLabel ? .mini : .regular)
        .labelsHidden(!showsLabel)
        .accessibilityLabel("Auto")
        .alert(Text(verbatim: Self.notice(limit: agentLimit)), isPresented: $confirming) {
            Button("Turn on Auto") { autoMode = true }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { labelsHidden() } else { self }
    }
}
