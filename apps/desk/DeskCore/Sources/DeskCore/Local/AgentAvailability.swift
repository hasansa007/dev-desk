import Foundation

/// Whether an agent can actually be started, and in the same words for every caller that asks.
///
/// The rule the app got wrong: installed is not the same as usable. A CLI that is installed but signed out
/// starts, prints its own login prompt, and waits — so the Start button was enabled for a run that could
/// never finish. `InsightsAgent` already refused a signed-out agent for exactly this reason; the task path,
/// which is the one people press, did not. Under ADR 0036 it stops being a poor experience and becomes
/// impossible: a protocol session has no terminal for a human to answer a login prompt in.
///
/// Pure, so it is testable: the preferences that feed it are read in the app layer, the way `RunModeChoice`
/// already splits reading a preference from deciding with it.
public enum AgentAvailability: Equatable {
    case ready(AgentKind)
    case unavailable(reason: String)

    /// `connectionName` is what Settings calls the agent ("Claude"), `standIn` is a Debug build's stand-in
    /// executable, which runs in place of the CLI and so needs neither an install nor a sign-in.
    public static func resolve(connectionName name: String, connections: [Connection],
                               hasStandIn: Bool = false) -> AgentAvailability {
        guard let agent = AgentLaunch.agent(forConnectionName: name) else {
            return .unavailable(reason: name == "Gemini"
                                ? "Gemini has no confirmed way to run the dev pipeline, so Dev Desk doesn't start it."
                                : "\(name) isn't installed here, so Dev Desk can't start it.")
        }
        if hasStandIn { return .ready(agent) }

        let connection = connections.first { $0.id == agent.rawValue }
        guard connection?.state == .detected else {
            return .unavailable(reason: "\(AgentLaunch.displayName(agent)) isn't installed here, so Dev Desk can't start it.")
        }
        // The CLI's own words where it has them — it knows whether it is logged out, expired or rate-limited
        // better than this sentence does.
        if let connection, connection.isSignedOut {
            return .unavailable(reason: connection.detail
                ?? "\(AgentLaunch.displayName(agent)) is installed but not signed in. Sign in from Settings → Accounts.")
        }
        return .ready(agent)
    }
}
