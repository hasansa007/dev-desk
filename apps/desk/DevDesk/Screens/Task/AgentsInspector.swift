import DeskCore
import SwiftUI

struct AgentsInspector: View {
    let model: ProjectWindowModel
    let task: DeskTask
    let sideDockFallsBack: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Agents")
            if task.agents.isEmpty {
                if let note = task.agentsNote {
                    Text(note)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(task.agents) { agent in
                        TaskAgentCard(agent: agent) { action in
                            Button(action.rawValue) { model.perform(action, agentID: agent.id) }
                                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                                .fixedSize()
                                .disabled(unavailableReason(action) != nil)
                                .help(help(for: action))
                        }
                    }
                }
                .padding(.top, 10)
            }
            if !task.dependencies.isEmpty {
                SectionLabel("Dependencies")
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(task.dependencies, id: \.self) { dependency in
                        MarkdownText(dependency.text, font: DeskFont.secondary, color: DeskColor.secondaryInk)
                            .lineSpacing(4.3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            }
            SectionLabel("Dock placement")
                .padding(.top, 16)
            HStack(spacing: 6) {
                placementButton("Bottom", .bottom)
                placementButton("Side", .side)
            }
            .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isDemo: Bool { model.snapshot?.isDemo ?? false }

    private func unavailableReason(_ action: AgentAction) -> String? {
        switch action {
        case .openTerminal: return task.dock == nil ? "No session views for this task" : nil
        case .viewActivity: return task.dock?.splitTabID == nil ? "No activity view for this helper" : nil
        case .stop, .continueSession: return isDemo ? nil : "Dev Desk does not control agent processes"
        case .requestFollowUp, .readResult: return nil
        }
    }

    private func help(for action: AgentAction) -> String {
        if let reason = unavailableReason(action) { return reason }
        switch action {
        case .openTerminal: return "Show this session's terminal in the dock"
        case .viewActivity: return "Show this helper's read-only activity beside the terminal"
        case .continueSession: return "Demo only: adds a note to Activity. No session is resumed."
        case .stop: return "Demo only: adds a note to Activity. No process is touched."
        case .requestFollowUp: return "Draft a follow-up routed through the coordinating agent"
        case .readResult: return "Open the Evidence tab"
        }
    }

    private func placementButton(_ title: String, _ placement: DockPlacement) -> some View {
        let isSelected = model.dockPlacement == placement
        return Button(title) { model.setDockPlacement(placement) }
            .buttonStyle(DeskButtonStyle(kind: isSelected ? .primary : .secondary, size: .mini))
            .fixedSize()
            .disabled(task.dock == nil)
            .help(placementHelp(placement))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func placementHelp(_ placement: DockPlacement) -> String {
        if task.dock == nil { return "No session views for this task" }
        if placement == .side && sideDockFallsBack {
            return "The window is narrower than 1,200 points, so the dock stays at the bottom"
        }
        return placement == .bottom ? "Show the dock below the task" : "Show the dock beside the task"
    }
}

private struct TaskAgentCard<ActionButton: View>: View {
    let agent: AgentSession
    @ViewBuilder let actionButton: (AgentAction) -> ActionButton

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    StatusDot(tone: agent.tone, pulses: agent.pulses)
                    Text(agent.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DeskColor.ink)
                    Spacer(minLength: 0)
                    Text(agent.role)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                }
                Text(agent.stateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !agent.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(agent.actions, id: \.self) { action in
                        actionButton(action)
                    }
                }
                .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskCard(padding: 11)
    }
}
