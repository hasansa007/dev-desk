import DeskCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    let model: ProjectWindowModel
    /// Handed in rather than read from the environment: a toolbar item that silently found nil would be a
    /// play button that does nothing, which is the one failure this control must not have.
    let terminals: ShellTerminalRegistry?

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
        // The reload ring lived here, spending its life counting down to an automatic reload nobody had asked
        // about. Reloading is a pull at the top of the screen now, and ⌘R in the Project menu.
        // `#available` cannot rescue a symbol the SDK lacks: ToolbarSpacer is macOS 26 API and CI builds on
        // Xcode 16.4 (macOS 15 SDK), where it does not exist to be referenced. Swift 6.2 ships with that SDK.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Run and the panel toggles are separate capsules: an action on the project is not a view of it.
            // A ToolbarSpacer between them, fixed or flexible, left all four glyphs in one shared glass, so
            // run opts out of the shared background and draws its own.
            ToolbarItem(placement: .primaryAction) {
                RunProjectControl(model: model, terminals: terminals)
                    .padding(.horizontal, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
            panelToggles
        } else {
            legacyRunAndPanels
        }
        #else
        legacyRunAndPanels
        #endif
    }

    @ToolbarContentBuilder private var legacyRunAndPanels: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            RunProjectControl(model: model, terminals: terminals)
        }
        ToolbarItem(placement: .primaryAction) {
            Divider().frame(height: 16)
        }
        panelToggles
    }

    /// The Files edge, top right. The sidebar's own toggle sits beside the traffic lights, so a second one here was a duplicate.
    private var panelToggles: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
            // The size of the sidebar toggle macOS draws at the other end of the toolbar, so the two read as a pair.
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
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
