import DeskCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "desk.appearance"
    static let terminalFontSize = "desk.terminalFontSize"
    static let showSamples = "desk.showSamples"
    static let defaultConnection = "desk.defaultConnection"
    static let notifyDecisions = "desk.notifyDecisions"
    static let notifyCompletion = "desk.notifyCompletion"
    static let notifyFailures = "desk.notifyFailures"
    static let worktreeLocation = "desk.worktreeLocation"
    static let agentLimit = "desk.agentLimit"

    static func connectionOverride(_ ref: ProjectRef) -> String { "desk.connectionOverride.\(ref.id)" }
    static func autoMode(_ ref: ProjectRef) -> String { "desk.autoMode.\(ref.id)" }
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

/// The agent a project's Agents tab and Auto run: the project's override unless it's empty ("Use app default"), else the app default.
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

    /// What the saved preferences choose for `ref` now.
    static func current(for ref: ProjectRef, connections: [Connection]) -> AgentChoice {
        let defaults = UserDefaults.standard
        return resolve(override: defaults.string(forKey: PreferenceKey.connectionOverride(ref)) ?? "",
                       defaultConnection: defaults.string(forKey: PreferenceKey.defaultConnection) ?? "Codex",
                       connections: connections)
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
