import Foundation

/// What can carry a `TaskLaunch` right now, as the start sheet's two lists.
///
/// TODAY that is the CLIs the door starts in a session this app hosts — the same ones `AgentAvailability`
/// will let a Start dispatch, so the sheet can never offer a row that the Start then refuses. The ACP
/// adapters `AcpDetection` finds join `here` when `ACPSession` exists (ADR 0036 step 3); until then listing
/// them would name a substrate that is not built, which is the kind of claim this ADR exists to stop.
public enum StartRunners {
    /// `handoff` comes from the launchers `AcpDetection` probes, so the two lists have one source each.
    ///
    /// `terminalAgents` are the other CLIs found on this Mac. They run in the same built-in terminal, but the queue can
    /// only park a Claude or Codex launch, so with no free slot they are shown unavailable rather than queued.
    public static func choices(connections: [Connection], handoff: [RunnerOption] = [],
                               terminalAgents: [TerminalAgent] = [], hasFreeSlot: Bool = true) -> RunnerChoices {
        let known = AgentLaunch.runnableKinds.map { kind -> RunnerOption in
            let name = AgentLaunch.displayName(kind)
            switch AgentAvailability.resolve(connectionName: AgentLaunch.connectionName(kind),
                                             connections: connections) {
            case .ready:
                // "terminal", not "acp v1": it runs in a session the app hosts, which is what is true today.
                return RunnerOption(id: kind.rawValue, name: name, detail: "terminal", kind: .here)
            case .unavailable(let reason):
                return RunnerOption(id: kind.rawValue, name: name, detail: shortReason(reason), kind: .here,
                                    isAvailable: false)
            }
        }
        // Installed is all that can be known: none of these publishes a sign-in check this app reads, and a run that
        // needs one shows the tool's own prompt in the terminal, in Sessions, where it can be answered.
        let others = terminalAgents.map {
            RunnerOption(id: $0.rawValue, name: $0.name, detail: hasFreeSlot ? "terminal" : "no free slot", kind: .here,
                         isAvailable: hasFreeSlot)
        }
        let rows = known + others
        return RunnerChoices(here: rows, handoff: handoff,
                             hereEmptyReason: rows.contains(where: \.isAvailable) ? nil : emptyReason(rows))
    }

    /// A row's note has a row's worth of space, so the sentence becomes a label; the whole reason stays in
    /// the connection's own detail, where the Accounts pane already shows it.
    static func shortReason(_ reason: String) -> String {
        if reason.contains("not signed in") || reason.contains("signed in") { return "not signed in" }
        if reason.contains("isn't installed") { return "not installed" }
        if reason.contains("no confirmed way") { return "not supported" }
        return "unavailable"
    }

    /// Never a bare "nothing available": the sheet says which of the two it is, because the fixes differ.
    static func emptyReason(_ rows: [RunnerOption]) -> String {
        let signedOut = rows.filter { $0.detail == "not signed in" }.map(\.name)
        guard signedOut.isEmpty else {
            return "\(signedOut.joined(separator: " and ")) \(signedOut.count == 1 ? "is" : "are") installed but not signed in. "
                + "Sign in from Settings → Accounts, or hand this task to a tool below."
        }
        return "No agent CLI is installed here, so nothing can run this task in Dev Desk. Hand it to a tool below."
    }
}
