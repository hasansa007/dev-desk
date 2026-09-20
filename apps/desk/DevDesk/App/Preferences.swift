import DeskCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "desk.appearance"
    static let appIcon = "desk.appIcon"
    static let terminalFontSize = "desk.terminalFontSize"
    static let defaultConnection = "desk.defaultConnection"
    static let runMode = "desk.runMode"
    static let notifyDecisions = "desk.notifyDecisions"
    static let notifyCompletion = "desk.notifyCompletion"
    static let notifyFailures = "desk.notifyFailures"
    /// A macOS system sound's name, or "" for none. Played by the app, so it sounds even when the banner is skipped.
    static let notifySound = "desk.notifySound"
    static let worktreeLocation = "desk.worktreeLocation"
    static let agentLimit = "desk.agentLimit"
    /// The most agents one findings or ideation run may start (ADR 0043).
    static let runMaxAgents = "desk.runMaxAgents"
    static let confirmQuit = "desk.confirmQuit"
    /// Reload every two minutes. Off by default: the board is brought up to date by what you do, not by a clock.
    static let autoReload = "desk.autoReload"
    static let sidebarRail = "desk.sidebarRail"
    static let findingsGrouping = "desk.findingsGrouping"
    /// The developer's "Start with" list, as `StartWithList` JSON, for every project.
    static let startWith = "desk.startWith"
    /// Which agent background runs use: Claude or Codex, apart from the default connection.
    static let backgroundConnection = "desk.backgroundConnection"

    /// The two override keys are no longer read — the connection and the mode are the app's, for every project —
    /// but a key function is how a stored value is found, and one already written stays findable.
    static func connectionOverride(_ ref: ProjectRef) -> String { "desk.connectionOverride.\(ref.id)" }
    static func runModeOverride(_ ref: ProjectRef) -> String { "desk.runModeOverride.\(ref.id)" }
    static func autoMode(_ ref: ProjectRef) -> String { "desk.autoMode.\(ref.id)" }
    /// The run sheet's stop choices for one door in one project, e.g. `decide,skip,skip`.
    static func runStops(_ ref: ProjectRef, door: String) -> String { "desk.runStops.\(door).\(ref.id)" }
}

/// What a fresh install runs before anything is chosen. It was written out at every site that read the
/// preference — the dialog, the Settings pane, the resolver — so a change of default meant finding all three.
enum AgentDefaults {
    static let connection = "Codex"
    static let runMode: RunMode = .standard
    /// Repeated at eleven @AppStorage sites before this existed. A launch is built outside a view and
    /// has to read the same default, and a default that disagrees with itself is how a queued card
    /// starts somewhere its Start never named.
    static let worktreeLocation = "~/.devdesk/wt"
}

/// The agent background runs use — Findings or Ideation run in the background, filing, a diagram. Only Claude and Codex
/// have a headless form whose output this app reads, so this is its own setting rather than the default connection:
/// a default of Gemini must not quietly become Codex for a background run. Never chosen, it shows — in Settings, where
/// it can be changed — the default when that can run in the background, and Codex otherwise.
enum BackgroundConnection {
    static var choices: [String] { DoorCommand.agents.map(\.name) }

    static func resolve(stored: String, defaultConnection: String) -> String {
        if choices.contains(stored) { return stored }
        return choices.contains(defaultConnection) ? defaultConnection : AgentDefaults.connection
    }

    static var current: String {
        let defaults = UserDefaults.standard
        return resolve(stored: defaults.string(forKey: PreferenceKey.backgroundConnection) ?? "",
                       defaultConnection: defaults.string(forKey: PreferenceKey.defaultConnection) ?? AgentDefaults.connection)
    }
}

/// How many agents may run at once, across every window.
enum AgentLimit {
    static let defaultValue = 3
    static let range = 1...6

    static var current: Int {
        let stored = UserDefaults.standard.object(forKey: PreferenceKey.agentLimit) as? Int ?? defaultValue
        return min(max(stored, range.lowerBound), range.upperBound)
    }
}

/// The agent a project's Agents tab and Auto run: the app default, for every project. A per-project override
/// was one more place to look when a run started the wrong agent, and never the place anyone looked first —
/// `resolve` still takes one so its rule stays written down and testable, but nothing reads a stored override.
/// Any of the five agents, only when installed, and only through a login shell Dev Desk can drive.
enum AgentChoice: Equatable {
    case ready(AgentKind)
    case unavailable(reason: String)

    static func resolve(override: String, defaultConnection: String, connections: [Connection],
                        terminalAgents: [TerminalAgent] = []) -> AgentChoice {
        let name = override.isEmpty ? defaultConnection : override
        // The rule itself lives in DeskCore, where it is tested; this reads the preferences it needs.
        // A Debug build's stand-in runs in place of the CLI, so the CLI needs neither install nor sign-in.
        switch AgentAvailability.resolve(connectionName: name, connections: connections,
                                         hasStandIn: DebugLaunch.agentExecutable != nil, terminalAgents: terminalAgents) {
        case .unavailable(let reason): return .unavailable(reason: reason)
        case .ready(let agent):
            if let reason = LoginShell.unsupportedReason { return .unavailable(reason: reason) }
            return .ready(agent)
        }
    }

    /// What the saved preferences choose for `ref` now: the app default, which every project shares.
    static func current(for ref: ProjectRef, connections: [Connection], terminalAgents: [TerminalAgent] = []) -> AgentChoice {
        let defaults = UserDefaults.standard
        return resolve(override: "",
                       defaultConnection: defaults.string(forKey: PreferenceKey.defaultConnection) ?? AgentDefaults.connection,
                       connections: connections, terminalAgents: terminalAgents)
    }
}

/// Which run mode a project gets, resolved the same way a connection is: the app default, for every project.
/// DeskCore stays free of `UserDefaults` — it takes the mode as a parameter — so this reading of the preference
/// lives in the app layer beside the connection's.
enum RunModeChoice {
    /// An empty override string means "use app default"; so does any value that is not a mode we know.
    static func resolve(override: String, appDefault: RunMode) -> RunMode {
        RunMode(rawValue: override) ?? appDefault
    }

    /// What the saved preferences choose for `ref` now: the app default, since no override is read any more.
    static func current(for ref: ProjectRef) -> RunMode {
        let defaults = UserDefaults.standard
        return resolve(override: "",
                       appDefault: defaults.string(forKey: PreferenceKey.runMode).flatMap(RunMode.init(rawValue:)) ?? AgentDefaults.runMode)
    }
}

/// The model names the composer offers per agent. These are a curated convenience list, not fetched: the CLIs
/// (`claude`, `codex`) only accept `--model <name>` and have no way to list what they support, so Dev Desk
/// carries a small hand-kept set. Custom in the composer covers anything else the tool understands.
enum ModelCatalog {
    static func models(for agent: AgentKind) -> [String] {
        switch agent {
        case .claude: return ["claude-opus-4-20250514", "claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]
        case .codex: return ["gpt-5-codex", "o3", "o4-mini"]
        case .gemini, .opencode, .antigravity: return []
        }
    }
}

enum AppearanceChoice: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// App-wide, not per window: alerts, open panels and any window without the modifier follow it too. Only
    /// project windows applied the setting, so the Open Project window stayed light under Dark (2026-09-19).
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// The Appearance setting on a window: its colour scheme, and the app-wide appearance kept in step when it changes.
/// `override` is Snapshot mode's forced scheme.
struct AppliesAppearance: ViewModifier {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    var override: ColorScheme? = nil

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(override ?? appearance.colorScheme)
            .onAppear { effective.apply() }
            .onChange(of: appearance) { _, _ in effective.apply() }
    }

    /// A forced scheme (Snapshot mode) wins app-wide too, or AppKit-drawn parts would follow the stored setting.
    private var effective: AppearanceChoice {
        switch override {
        case .some(.light): return .light
        case .some(.dark): return .dark
        default: return appearance
        }
    }
}

/// Which artwork the app icon wears. `light` is the bundle's shipped icon; `dark` is the near-black
/// variant in `AppIconDark.imageset`, applied over the bundle at runtime (see `AppIconStyle`).
/// `system` follows whatever appearance the app is showing, resolved by `AppIconStyle` against the
/// appearance preference first and the OS appearance only when that is itself `system`.
enum AppIconChoice: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
