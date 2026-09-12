import DeskCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    let model: ProjectWindowModel
    @Binding var columns: NavigationSplitViewVisibility

    /// Counts only what is actually live, so the dot never claims a finished run is still going.
    private var liveRuns: Int {
        model.runs.runs.filter {
            switch model.shellSessions.state(for: $0.id) {
            case .running, .preparing: return true
            default: return false
            }
        }.count
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.present(.openProject) } label: {
                Label("Open project", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
        }
        if let summary = model.snapshot?.activitySummary {
            ToolbarItem(placement: .primaryAction) {
                ActivitySummary(badge: summary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            RefreshStatus(model: model)
        }
        // The countdown times the project; the three glyphs open panels. A rule keeps them from reading as one set.
        ToolbarItem(placement: .primaryAction) {
            Divider().frame(height: 16)
        }
        // The panel cluster, top right, one glyph per edge — where Xcode and every other Mac app keeps it.
        ToolbarItemGroup(placement: .primaryAction) {
            PanelToggle(symbol: "sidebar.leading", isOn: columns != .detailOnly,
                        label: "Sidebar", help: "Hide or show the project sidebar") {
                columns = columns == .detailOnly ? .all : .detailOnly
            }
            PanelToggle(symbol: "square.bottomhalf.filled", isOn: model.runsOpen, badge: liveRuns,
                        label: "Runs", help: runsHelp) {
                model.toggleRuns()
            }
            PanelToggle(symbol: "sidebar.trailing", isOn: model.filesOpen,
                        label: "Files", help: "Hide or show this project's files") {
                model.toggleFiles()
            }
        }
    }

    private var runsHelp: String {
        liveRuns > 0 ? "Hide or show the doors this project is running (\(liveRuns) live)"
                     : "Hide or show the doors this project has run"
    }
}

/// A toolbar glyph that shows whether its panel is open, the way a panel toggle does everywhere else.
private struct PanelToggle: View {
    let symbol: String
    let isOn: Bool
    var badge = 0
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .foregroundStyle(isOn ? DeskColor.accent : DeskColor.navInk)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Circle()
                            .fill(DeskColor.tone(.running).dot)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
    }
}

private struct ActivitySummary: View {
    let badge: StatusBadge

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(tone: badge.tone, pulses: badge.pulses)
            Text(badge.label)
        }
        .font(DeskFont.secondary)
        .foregroundStyle(DeskColor.navInk)
        .padding(.horizontal, 10)
        .controlChrome(height: 28)
        .accessibilityElement(children: .combine)
    }
}
