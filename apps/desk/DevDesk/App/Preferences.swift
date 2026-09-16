import DeskCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "desk.appearance"
    static let appIcon = "desk.appIcon"
    static let terminalFontSize = "desk.terminalFontSize"
    static let showSamples = "desk.showSamples"
    static let defaultConnection = "desk.defaultConnection"
    static let runMode = "desk.runMode"
    static let notifyDecisions = "desk.notifyDecisions"
    static let notifyCompletion = "desk.notifyCompletion"
    static let notifyFailures = "desk.notifyFailures"
    static let worktreeLocation = "desk.worktreeLocation"
    static let agentLimit = "desk.agentLimit"
    static let confirmQuit = "desk.confirmQuit"
    static let sidebarRail = "desk.sidebarRail"

    /// The two override keys are no longer read — the connection and the mode are the app's, for every project —
    /// but a key function is how a stored value is found, and one already written stays findable.
    static func connectionOverride(_ ref: ProjectRef) -> String { "desk.connectionOverride.\(ref.id)" }
    static func runModeOverride(_ ref: ProjectRef) -> String { "desk.runModeOverride.\(ref.id)" }
    static func autoMode(_ ref: ProjectRef) -> String { "desk.autoMode.\(ref.id)" }
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
/// Only Claude and Codex, only when installed, and only through a login shell Dev Desk can drive.
enum AgentChoice: Equatable {
    case ready(AgentKind)
    case unavailable(reason: String)

    static func resolve(override: String, defaultConnection: String, connections: [Connection]) -> AgentChoice {
        let name = override.isEmpty ? defaultConnection : override
        guard let agent = AgentLaunch.agent(forConnectionName: name) else {
            return .unavailable(reason: name == "Gemini"
                                ? "Gemini has no confirmed way to run the dev pipeline, so Dev Desk doesn't start it."
                                : "\(name) isn't installed here, so Dev Desk can't start it.")
        }
        // A Debug build's stand-in runs in place of the CLI, so the CLI itself needn't be there.
        let installed = connections.contains { $0.id == agent.rawValue && $0.state == .detected }
        guard installed || DebugLaunch.agentExecutable != nil else {
            return .unavailable(reason: "\(AgentLaunch.displayName(agent)) isn't installed here, so Dev Desk can't start it.")
        }
        if let reason = LoginShell.unsupportedReason { return .unavailable(reason: reason) }
        return .ready(agent)
    }

    /// What the saved preferences choose for `ref` now: the app default, which every project shares.
    static func current(for ref: ProjectRef, connections: [Connection]) -> AgentChoice {
        let defaults = UserDefaults.standard
        return resolve(override: "",
                       defaultConnection: defaults.string(forKey: PreferenceKey.defaultConnection) ?? AgentDefaults.connection,
                       connections: connections)
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
