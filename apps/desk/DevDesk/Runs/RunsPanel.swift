import DeskCore
import SwiftUI

enum RunsPlacement { case floating, docked }

/// Every door this window has started, with the selected one's terminal. It floats or docks, like Insights.
struct RunsPanel: View {
    @Bindable var model: ProjectWindowModel
    let placement: RunsPlacement

    private var selected: DoorRun? {
        model.runs.selectedID.flatMap { model.runs.run($0) } ?? model.runs.runs.first
    }

    var body: some View {
        let core = VStack(spacing: 0) {
            header
            if model.runs.runs.isEmpty {
                EmptyStateView(title: "Nothing running",
                               message: "Run survey in Findings, or Start task on a card, and it appears here.")
            } else {
                runList
                if let selected {
                    Rectangle().fill(DeskColor.divider).frame(height: 1)
                    ShellPane(sessions: model.shellSessions, id: selected.id, folderNote: selected.folderNote,
                              command: selected.command, startTitle: "Start run")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.surface)
        .onChange(of: endedRuns) { _, _ in Task { await model.load() } }

        switch placement {
        case .floating:
            core
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DeskColor.controlBorder))
                .shadow(color: .black.opacity(0.28), radius: 60, x: 0, y: 24)
        case .docked:
            core
                .overlay(alignment: .leading) { Rectangle().fill(DeskColor.border).frame(width: 1) }
                .shadow(color: .black.opacity(0.06), radius: 24, x: -8, y: 0)
        }
    }

    /// A finished run has written whatever it was going to write, so the project is read again.
    private var endedRuns: Int {
        model.runs.runs.filter {
            if case .ended = model.shellSessions.state(for: $0.id) { return true }
            return false
        }.count
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Runs").font(.system(size: 13, weight: .semibold)).foregroundStyle(DeskColor.ink)
            Text(placement == .floating ? "Floating over the workspace" : "Nonmodal · docked")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 8)
            Button(placement == .floating ? "Dock" : "Float") {
                placement == .floating ? model.dockRuns() : model.floatRuns()
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            Button("Close") { model.toggleRuns() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(placement == .floating ? DeskColor.titlebarFill : DeskColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(placement == .floating ? DeskColor.titlebarBorder : DeskColor.divider).frame(height: 1)
        }
    }

    private var runList: some View {
        VStack(spacing: 0) {
            ForEach(model.runs.runs) { run in
                runRow(run)
            }
        }
    }

    private func runRow(_ run: DoorRun) -> some View {
        let state = Self.label(for: model.shellSessions.state(for: run.id))
        let isSelected = run.id == selected?.id
        return Button { model.runs.selectedID = run.id } label: {
            HStack(spacing: 8) {
                StatusDot(tone: state.tone, pulses: state.pulses)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.title)
                        .font(DeskFont.body.weight(.semibold))
                        .foregroundStyle(DeskColor.ink)
                    Text("\(run.agent) · \(state.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                Spacer(minLength: 4)
                Button("Remove") { model.runs.remove(run.id) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .disabled(state.isLive)
                    .help(state.isLive ? "End the run in its terminal first" : "Remove this run from the list")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func label(for state: ShellSessionState) -> (label: String, tone: StatusTone, pulses: Bool, isLive: Bool) {
        switch state {
        case .idle: return ("Not started", .neutral, false, false)
        case .preparing: return ("Preparing the folder", .info, true, true)
        case .running: return ("Running", .running, true, true)
        case .ended(_, let status): return (status.map { "Ended (status \($0))" } ?? "Ended", .ended, false, false)
        case .failed(let reason): return (reason, .failed, false, false)
        }
    }
}

extension ProjectWindowModel {
    /// A sample project has no folder on disk, so no door can run in it.
    var canRunDoors: Bool {
        if case .local = ref { return true }
        return false
    }

    /// Lists the door as a run and opens the panel. Nothing executes until the pane's own Start, per ADR 0017.
    /// `id` separates runs of the same door for different tasks; the folder rule prefixes `folderNote` with where it opens.
    func prepareRun(door: String, title: String, agent: String, arguments: [String] = [],
                    id: String? = nil, folderNote: String? = nil) {
        guard canRunDoors,
              let command = DoorCommand.build(door: door, agent: agent, arguments: arguments, home: NSHomeDirectory())
        else { return }
        runs.add(DoorRun(id: id ?? "door:\(door)", title: title, agent: agent, command: command,
                         folderNote: folderNote ?? "a door reads the whole project, not one task's branch."))
        runsOpen = true
    }

    /// Why the button that would start `agent` is disabled, or nil when it can run.
    func runBlockedReason(agent: String) -> String? {
        if !canRunDoors { return "Sample projects have no folder, so there is nothing to run in." }
        if DoorCommand.agent(named: agent) == nil {
            return "\(agent) has no invocation this family has verified. Choose Claude or Codex in Settings."
        }
        return nil
    }
}
