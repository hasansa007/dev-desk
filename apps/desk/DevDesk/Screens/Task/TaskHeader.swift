import DeskCore
import SwiftUI

struct TaskHeader: View {
    let model: ProjectWindowModel
    let task: DeskTask
    let showsAgentsButton: Bool
    let sideDockFallsBack: Bool
    @Environment(\.openURL) private var openURL
    @State private var showsAgents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                Text(task.branchLine)
                    .font(DeskFont.mono(12))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.top, 7)
                HStack(spacing: 2) {
                    ForEach(TaskTab.allCases, id: \.self) { tab in
                        TaskTabButton(title: tab.title, isSelected: model.tab == tab) { model.tab = tab }
                    }
                }
                .padding(.top, 10)
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(DeskColor.divider)
                .frame(height: 1)
        }
        .background(DeskColor.surface)
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Button("‹ Board") { model.go(.board) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .fixedSize()
                .accessibilityLabel("Back to Board")
            Text(task.title)
                .font(DeskFont.title)
                .foregroundStyle(DeskColor.ink)
                .lineLimit(1)
            if !task.issueLabel.isEmpty {
                Text(task.issueLabel)
                    .font(DeskFont.mono(12))
                    .foregroundStyle(DeskColor.mutedInk)
                    .fixedSize()
            }
            StatusPill(badge: task.headerBadge, showsDot: false, verticalPadding: 2, horizontalPadding: 8)
            Spacer(minLength: 0)
            if let nextAction = task.nextAction {
                Button(nextAction.title) {
                    if let url = model.performNextAction() { openURL(url) }
                }
                .buttonStyle(DeskButtonStyle(kind: .primary))
                .fixedSize()
                .help(nextActionHelp(nextAction))
            }
            Button(dockIsShown ? "Hide agents dock" : "Show agents dock") { model.toggleDock() }
                .buttonStyle(DeskButtonStyle(kind: .secondary))
                .fixedSize()
                .disabled(task.dock == nil)
                .help(task.dock == nil ? "No session views for this task" : "Show or hide the Agents & Terminals dock")
            if showsAgentsButton {
                Button("Agents") { showsAgents.toggle() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary))
                    .fixedSize()
                    .help("Show this task's agents, dependencies and dock placement")
                    .popover(isPresented: $showsAgents, arrowEdge: .bottom) {
                        AgentsInspector(model: model, task: task, sideDockFallsBack: sideDockFallsBack)
                            .frame(width: DeskMetric.inspectorWidth)
                    }
            }
        }
    }

    private var dockIsShown: Bool { model.dockOpen && task.dock != nil }

    private func nextActionHelp(_ action: NextAction) -> String {
        guard case .openURL(let url, _) = action else { return "" }
        return url.absoluteString
    }
}

private struct TaskTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(DeskFont.body)
                    .foregroundStyle(isSelected ? DeskColor.ink : DeskColor.mutedInk)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                Rectangle()
                    .fill(isSelected ? DeskColor.accent : Color.clear)
                    .frame(height: 2)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
