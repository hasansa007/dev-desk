import DeskCore
import SwiftUI

struct ProjectToolbar: ToolbarContent {
    let model: ProjectWindowModel
    /// Handed in rather than read from the environment: a toolbar item that silently found nil would be a
    /// play button that does nothing, which is the one failure this control must not have.
    let terminals: ShellTerminalRegistry?

    /// What this project is doing right now, counted from its own live sessions. It used to read
    /// `snapshot.activitySummary`, which NOTHING but the StudyHub fixtures ever sets — so the one place it
    /// appeared it was the literal string "2 running · 1 waiting", which is why it read as a mock
    /// (2026-09-20, reported on screen). Nil when nothing is going, rather than a badge saying zero.
    private var activity: (label: String, tone: StatusTone, pulses: Bool)? {
        let live = SessionRow.all(in: model).filter(\.isLive)
        guard !live.isEmpty else { return nil }
        let waiting = live.count { model.waitingSessions.contains($0.id) }
        let running = live.count - waiting
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        // Waiting wins the colour: a run stopped on a question is the one that needs you.
        return (parts.joined(separator: " · "), waiting > 0 ? .waiting : .running, running > 0)
    }

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
        activityItem
        // The project's own run, before the panels: it is an action on the project, not a view of it.
        // The reload ring lived here, spending its life counting down to an automatic reload nobody had asked
        // about. Reloading is a pull at the top of the screen now, and ⌘R in the Project menu.
        // `#available` cannot rescue a symbol the SDK lacks: ToolbarSpacer is macOS 26 API and CI builds on
        // Xcode 16.4 (macOS 15 SDK), where it does not exist to be referenced. Swift 6.2 ships with that SDK.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Run and the panel toggles are separate items, and NEITHER takes a background. macOS 26 draws the
            // toolbar as glass: a pale capsule per item and a pale shared one behind the group, which on the
            // Console's near-black bar read as light chips floating in a dark strip (2026-09-20, on screen).
            // The controls carry their own chrome in Dev Desk's own colours, so the system's is turned off.
            // Which checkout, then what to do in it: the picker and play are separate items.
            ToolbarItem(placement: .primaryAction) {
                WorktreePicker(model: model)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                RunProjectControl(model: model, terminals: terminals)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
            panelToggles
                .sharedBackgroundVisibility(.hidden)
        } else {
            legacyRunAndPanels
        }
        #else
        legacyRunAndPanels
        #endif
    }

    /// The readout, with no capsule of its own. macOS 26 gave it the toolbar's glass pill, and a readout in a
    /// pill reads as a button you can press — the pill also sat tight against the text (2026-09-20, on screen,
    /// reported). Hidden here for the same reason it is hidden on Run and the panel toggles.
    @ToolbarContentBuilder private var activityItem: some ToolbarContent {
        if let summary = activity {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    ActivitySummary(summary: summary)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    ActivitySummary(summary: summary)
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                ActivitySummary(summary: summary)
            }
            #endif
        }
    }

    @ToolbarContentBuilder private var legacyRunAndPanels: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            WorktreePicker(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            Divider().frame(height: 16)
        }
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

/// The rail's own toggle, where macOS's sidebar toggle used to sit. The system's collapsed the rail out of
/// the window; Dev Desk's rail is either labels or icons, which is what ⇧⌘S has always meant here.
struct RailToggle: View {
    @Binding var isRail: Bool

    var body: some View {
        Button { isRail.toggle() } label: {
            Image(systemName: isRail ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isRail ? DeskColor.accent : DeskColor.navInk)
        }
        .help(isRail ? "Show the rail's labels (⇧⌘S)" : "Icons only (⇧⌘S)")
        .accessibilityLabel("Compact Sidebar")
        .accessibilityValue(isRail ? "On" : "Off")
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
                .font(.system(size: 15, weight: .regular, design: .monospaced))
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

/// What this project is doing, in its own tone. No chrome at all: it wore `controlChrome` (the app's BUTTON
/// chrome) and then a tinted capsule, and both read as something you could press. It is a readout — a dot
/// and a count — and the dot carries the colour (2026-09-20, on screen).
private struct ActivitySummary: View {
    let summary: (label: String, tone: StatusTone, pulses: Bool)

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(tone: summary.tone, pulses: summary.pulses)
            Text(summary.label)
        }
        .font(DeskFont.secondary)
        .foregroundStyle(DeskColor.tone(summary.tone).foreground)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
