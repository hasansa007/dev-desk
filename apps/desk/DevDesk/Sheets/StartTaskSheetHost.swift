import AppKit
import DeskCore
import SwiftUI

/// Assembles what `StartSheet` draws — the launch, who may carry it, the slot line — and dispatches the
/// choice. The sheet itself stays a pure view over values; everything that reads a preference or starts a
/// process is here (ADR 0036 §4.8 moment 1).
struct StartTaskSheetHost: View {
    @Bindable var model: ProjectWindowModel
    let taskID: String
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    /// Set when Automation was refused and a hand-off's command went to the clipboard instead: the sheet stays open
    /// and says so, because closing it would look as though the task had started.
    @State private var copied = false

    var body: some View {
        if let task = model.task(taskID), let launch = model.taskLaunch(for: task, agent: defaultConnection) {
            StartSheet(launch: launch,
                       choices: StartRunners.choices(connections: model.snapshot?.connections ?? [],
                                                     handoff: handoffOptions),
                       prompt: launch.prompt(home: NSHomeDirectory()) ?? "",
                       slots: StartSlots(running: LiveShells.shared.agentCount, limit: AgentLimit.current),
                       isFirstStart: !model.remembersLaunch(for: task),
                       notice: copied ? "Couldn't open your terminal, so the command is on the clipboard — paste it into a terminal to start." : nil,
                       onCancel: model.dismissSheet,
                       onStart: { runner in start(task, launch: launch, with: runner) })
        } else {
            SheetChrome(title: "Start task", confirmTitle: "Start", confirmDisabled: true,
                        onCancel: model.dismissSheet, onConfirm: {}) {
                UnavailableView(reason: "This card has no issue number or backlog entry, so `/dev` has nothing to open.")
            }
        }
    }

    /// Only the hand-off CLIs actually on this Mac. The other launchers `AcpDetection` knows — Terminal, editors,
    /// super.engineering — are not offered: nothing is wired to hand them a task yet.
    private var handoffOptions: [RunnerOption] {
        (model.snapshot?.handoffAgents ?? []).map {
            RunnerOption(id: $0.rawValue, name: $0.name, detail: "your terminal", kind: .handoff)
        }
    }

    /// A `.here` row runs the task in this window; a `.handoff` row types it into the developer's own terminal.
    private func start(_ task: DeskTask, launch: TaskLaunch, with runner: RunnerOption) {
        if runner.kind == .handoff {
            guard let agent = HandoffAgent(rawValue: runner.id) else { return }
            if case .copied = model.handOff(task, launch: launch, to: agent) { copied = true }
            return
        }
        guard let agent = AgentKind(rawValue: runner.id) else { return }
        // The chosen runner, not the preference: this is the whole point of choosing one.
        var chosen = launch
        if agent != launch.agent {
            chosen = TaskLaunch(id: launch.id, task: launch.task, title: launch.title, door: launch.door,
                                arguments: launch.arguments, agent: agent, mode: launch.mode,
                                worktreeLocation: launch.worktreeLocation, base: launch.base)
        }
        model.startTask(task, with: chosen)
    }
}
