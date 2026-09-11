import DeskCore
import SwiftUI

struct AgentsDock: View {
    let model: ProjectWindowModel
    let dock: DockContent
    let placement: DockPlacement

    var body: some View {
        let edge = placement == .bottom ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        edge {
            paneRule
            VStack(spacing: 0) {
                bar
                Rectangle()
                    .fill(DeskColor.terminalPaneBorder)
                    .frame(height: 1)
                panes
            }
        }
        .background(DeskColor.terminalGround)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agents & Terminals")
    }

    private var selectedTab: DockTab? {
        dock.tabs.first { $0.id == model.dockTabID } ?? dock.tabs.first
    }

    private var canSplit: Bool {
        guard let id = dock.splitTabID else { return false }
        return dock.tabs.contains { $0.id == id }
    }

    private var splitTab: DockTab? {
        guard model.dockSplit, let id = dock.splitTabID else { return nil }
        return dock.tabs.first { $0.id == id }
    }

    private var primaryTab: DockTab? {
        guard let splitTab, selectedTab?.id == splitTab.id else { return selectedTab }
        return dock.tabs.first { $0.id != splitTab.id }
    }

    private var paneRule: some View {
        Rectangle()
            .fill(DeskColor.terminalPaneBorder)
            .frame(width: placement == .side ? 1 : nil, height: placement == .bottom ? 1 : nil)
    }

    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                tabStrip
                Spacer(minLength: 0)
                caption
                    .lineLimit(1)
                controls
            }
            .frame(height: 33)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        tabStrip
                            .frame(maxHeight: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    controls
                }
                .frame(height: 33)
                caption
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.terminalBar)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(dock.tabs) { tab in
                TaskDockTabButton(title: tab.title, isSelected: tab.id == selectedTab?.id) { model.dockTabID = tab.id }
            }
        }
        .fixedSize()
    }

    private var caption: some View {
        Text(dock.caption)
            .font(.system(size: 11))
            .foregroundStyle(DeskColor.terminalDim)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(splitTab == nil ? "Split panes" : "Single pane") { model.toggleSplit() }
                .disabled(!canSplit)
                .help(canSplit ? "Show a second view of this session alongside the first" : "This task has no second session view to split")
            Button("Hide") { model.toggleDock() }
                .help("Hide the Agents & Terminals dock")
        }
        .buttonStyle(TaskDockControlStyle())
        .fixedSize()
    }

    @ViewBuilder private var panes: some View {
        let layout = placement == .bottom ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            if let primaryTab {
                pane(primaryTab)
            }
            if let splitTab {
                if primaryTab != nil {
                    Rectangle()
                        .fill(DeskColor.terminalPaneBorder)
                        .frame(width: placement == .bottom ? 1 : nil, height: placement == .side ? 1 : nil)
                }
                pane(splitTab)
            }
        }
    }

    private func pane(_ tab: DockTab) -> some View {
        TerminalTranscriptView(transcript: tab.transcript)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tab.id)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tab.title)
    }
}

private struct TaskDockTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        Button(action: action) {
            Text(title)
                .font(DeskFont.small)
                .foregroundStyle(isSelected ? Color.white : DeskColor.terminalDim2)
                .lineLimit(1)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(isSelected ? DeskColor.accent : Color.clear, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TaskDockControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TaskDockControlBody(configuration: configuration)
    }
}

private struct TaskDockControlBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(DeskColor.terminalInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(DeskColor.terminalControlFill, in: shape)
            .overlay(shape.strokeBorder(DeskColor.terminalControlBorder))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
    }
}
