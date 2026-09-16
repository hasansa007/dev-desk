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

    var body: some View {
        if let task = model.task(taskID), let launch = model.taskLaunch(for: task, agent: defaultConnection) {
            StartSheet(launch: launch,
                       choices: StartRunners.choices(connections: model.snapshot?.connections ?? []),
                       prompt: launch.prompt(home: NSHomeDirectory()) ?? "",
                       slots: StartSlots(running: LiveShells.shared.agentCount, limit: AgentLimit.current),
                       isFirstStart: !model.remembersLaunch(for: task),
                       onCancel: model.dismissSheet,
                       onStart: { runner in start(task, launch: launch, with: runner) })
        } else {
            SheetChrome(title: "Start task", confirmTitle: "Start", confirmDisabled: true,
                        onCancel: model.dismissSheet, onConfirm: {}) {
                UnavailableView(reason: "This card has no issue number or backlog entry, so `/dev` has nothing to open.")
            }
        }
    }

    /// A `.here` row runs the task in this window. A `.handoff` row is not wired yet — the launchers land
    /// with *Continue in ▾* (ADR 0036 step 6), and until then the sheet must not pretend one started.
    private func start(_ task: DeskTask, launch: TaskLaunch, with runner: RunnerOption) {
        guard runner.kind == .here, let agent = AgentKind(rawValue: runner.id) else { return }
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
