import DeskCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    let model: ProjectWindowModel
    /// Handed in rather than read from the environment: a toolbar item that silently found nil would be a
    /// play button that does nothing, which is the one failure this control must not have.
    let terminals: ShellTerminalRegistry?
    @Binding var columns: NavigationSplitViewVisibility

    /// Counts only what is actually live, so the dot never claims a finished run is still going.
    private var liveRuns: Int {
        model.runs.runs.filter {
            switch model.sessions.state(for: $0.id) {
            case .running, .preparing: return true
            default: return false
            }
        }.count
    }

    var body: some ToolbarContent {
        if let summary = model.snapshot?.activitySummary {
            ToolbarItem(placement: .primaryAction) {
                ActivitySummary(badge: summary)
            }
        }
        // The project's own run, before the panels: it is an action on the project, not a view of it.
        ToolbarItem(placement: .primaryAction) {
            RunProjectControl(model: model, terminals: terminals)
        }
        // The reload ring lived here, spending its life counting down to an automatic reload nobody had asked
        // about. Reloading is a pull at the top of the screen now, and ⌘R in the Project menu.
        // `#available` cannot rescue a symbol the SDK lacks: ToolbarSpacer is macOS 26 API and CI builds on
        // Xcode 16.4 (macOS 15 SDK), where it does not exist to be referenced. Swift 6.2 ships with that SDK.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Flexible, not fixed: the countdown times the project and the three glyphs open panels. Adjacent,
            // they read as one set of four controls however they are separated, so they are pushed apart.
            ToolbarSpacer(.flexible, placement: .primaryAction)
        } else {
            ToolbarItem(placement: .primaryAction) {
                Divider().frame(height: 16)
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Divider().frame(height: 16)
        }
        #endif
        // The panel cluster, top right, one glyph per edge — where Xcode and every other Mac app keeps it.
        ToolbarItemGroup(placement: .primaryAction) {
            PanelToggle(symbol: "sidebar.leading", isOn: columns != .detailOnly,
                        label: "Sidebar", help: "Hide or show the project sidebar") {
                columns = columns == .detailOnly ? .all : .detailOnly
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
