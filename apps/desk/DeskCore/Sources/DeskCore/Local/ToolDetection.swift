import Foundation

/// Which agent CLIs are on this Mac, who they are signed in as, and the GitHub row. Nothing here holds a
/// credential: each CLI owns its own, and the app only reads what that CLI is willing to say (ADR 0013's rule
/// about reading the tools you already have, applied to accounts).
enum ToolDetection {
    /// Only the CLIs Dev Desk can run. Gemini and opencode were rows here and ran nothing — the app starts Claude and
    /// Codex alone — so they left on 2026-09-16 and return when an ACP session exists to carry them (ADR 0036 step 3).
    /// Their sign-in reading is in git at 5aaa4f5. They run tasks today as `TerminalAgent`s.
    static let tools: [(id: String, name: String)] = [("codex", "Codex"), ("claude", "Claude")]
    static let note = "Detected on this Mac. Dev Desk never stores credentials: signing in runs the tool's own command in your terminal, where you can watch it."

    /// The commands each CLI publishes for this, verified against their own `--help` rather than assumed
    /// (checked again 2026-09-16). `status` is nil for a CLI that publishes no non-interactive check, and
    /// `interactive` marks a sign-in that opens the tool's own session instead of completing by itself.
    static func auth(for id: String) -> (signIn: String, signOut: String?, status: [String]?, interactive: Bool)? {
        switch id {
        case "codex": return ("codex login", "codex logout", ["login", "status"], false)
        case "claude": return ("claude auth login", "claude auth logout", ["auth", "status"], false)
        default: return nil
        }
    }

    static let capabilities: CapabilityMatrix = {
        let unvalidated = [CapabilityValue](repeating: .notValidated, count: tools.count)
        return CapabilityMatrix(
            providers: tools.map(\.name),
            rows: [
                CapabilityRow(id: "terminal", name: "Interactive terminal", values: unvalidated),
                CapabilityRow(id: "resume", name: "Resume an ended session", values: unvalidated),
                CapabilityRow(id: "attach", name: "Attach to an external session", values: unvalidated),
            ],
            note: "No agent integration has been validated. Capabilities will be read from a connection once one exists.")
    }()

    static func detect(runner: CommandRunner) async -> [Connection] {
        await tools.concurrentMap { tool in
            let found = (try? await runner.run("which", [tool.id], in: nil, timeout: CommandTimeout.git))?.succeeded ?? false
            guard found else {
                return Connection(id: tool.id, name: tool.name, state: .missing, label: "not found")
            }
            guard let auth = auth(for: tool.id) else {
                // Found, and still not something this family will start: saying only "CLI found" read as ready.
                return Connection(id: tool.id, name: tool.name, state: .detected, label: "found · not supported",
                                  detail: "\(tool.name) has no confirmed way to run the dev pipeline, so Dev Desk doesn't start it.")
            }
            guard let statusCommand = auth.status else {
                // No status verb to ask, so the app does not know and must not claim. `isSignedOut` stays
                // false: refusing to start a CLI that may be perfectly signed in would be the worse guess.
                return Connection(id: tool.id, name: tool.name, state: .detected, label: "found · sign-in not readable",
                                  detail: "\(tool.name) publishes no way to check its sign-in, so Dev Desk can't tell. "
                                      + "Opening it shows you.",
                                  auth: ConnectionAuth(signIn: auth.signIn, signOut: auth.signOut,
                                                       isInteractive: auth.interactive))
            }
            let status = try? await runner.run(tool.id, statusCommand, in: nil, timeout: CommandTimeout.git)
            let output = status.map { $0.stdout + "\n" + $0.stderr } ?? ""
            let identity = AuthStatus.identity(from: output, tool: tool.id)
            // A CLI that answers with nothing has not said it is signed out — it has said nothing. Claiming
            // "not signed in" from silence is how a working install gets a Start disabled under it, and the
            // `opencode` on this Mac's PATH does exactly that: exit 0, no output, from a different build than
            // the one on a developer's own PATH.
            if identity == nil, output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Connection(id: tool.id, name: tool.name, state: .detected, label: "found · sign-in not readable",
                                  detail: "\(tool.name) answered its own status check with nothing, so Dev Desk can't "
                                      + "tell whether it is signed in. Opening it shows you.",
                                  auth: ConnectionAuth(signIn: auth.signIn, signOut: auth.signOut,
                                                       isInteractive: auth.interactive))
            }
            let signedIn = identity != nil
            return Connection(id: tool.id, name: tool.name, state: .detected,
                              label: signedIn ? (identity ?? "signed in") : "not signed in",
                              detail: signedIn ? nil : "\(tool.name) is installed but not signed in; a run would stop at its own prompt.",
                              auth: ConnectionAuth(signIn: auth.signIn, signOut: auth.signOut, identity: identity,
                                                   isInteractive: auth.interactive),
                              isSignedOut: !signedIn)
        }
    }

    static func github(_ state: GitHubState) -> Connection {
        let auth = ConnectionAuth(signIn: "gh auth login", signOut: "gh auth logout")
        switch state {
        case .ready: return Connection(id: "github", name: "GitHub", state: .connected, label: "connected", auth: auth)
        case .unavailable(let reason):
            // Signing in fixes a sign-in. It does not conjure a remote, and offering it for "no GitHub remote"
            // sends the developer to an account screen for a repository problem.
            let signedOut = state.isAuthFailure
            return Connection(id: "github", name: "GitHub", state: .unavailable,
                              label: state.shortUnavailableReason ?? reason,
                              detail: [reason, state.unavailableRemedy].compactMap { $0 }.joined(separator: " "),
                              auth: signedOut ? auth : nil,
                              isSignedOut: signedOut)
        }
    }
}

/// Reading who a CLI says it is. Each answers in its own shape, so each is read in its own way — and a shape
/// that changes leaves no identity rather than a wrong one.
enum AuthStatus {
    static func identity(from output: String, tool: String) -> String? {
        switch tool {
        case "claude": return claude(output)
        case "codex": return codex(output)
        default: return nil
        }
    }

    /// `claude auth status` answers in JSON: {"loggedIn": true, "authMethod": "claude.ai", "email": "…"}.
    static func claude(_ output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["loggedIn"] as? Bool == true else { return nil }
        if let email = object["email"] as? String, !email.isEmpty { return email }
        if let method = object["authMethod"] as? String, !method.isEmpty { return "signed in · \(method)" }
        return "signed in"
    }

    /// `codex login status` answers in one line: "Logged in using ChatGPT".
    static func codex(_ output: String) -> String? {
        let line = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, line.lowercased().hasPrefix("logged in") else { return nil }
        if let range = line.range(of: "using ") {
            return "signed in · " + line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return "signed in"
    }
}
