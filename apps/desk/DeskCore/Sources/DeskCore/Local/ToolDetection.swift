import Foundation

/// Which agent CLIs are on this Mac, who they are signed in as, and the GitHub row. Nothing here holds a
/// credential: each CLI owns its own, and the app only reads what that CLI is willing to say (ADR 0013's rule
/// about reading the tools you already have, applied to accounts).
enum ToolDetection {
    static let tools: [(id: String, name: String)] = [("codex", "Codex"), ("claude", "Claude"), ("gemini", "Gemini")]
    static let note = "Detected on this Mac. Dev Desk never stores credentials: signing in runs the tool's own command in a terminal you can watch."

    /// The commands each CLI publishes for this, verified against their own `--help` rather than assumed.
    /// Gemini has none here because the family has no verified way to run the pipeline with it, so there is
    /// nothing for a sign-in to enable.
    static func auth(for id: String) -> (signIn: String, signOut: String, status: [String])? {
        switch id {
        case "codex": return ("codex login", "codex logout", ["login", "status"])
        case "claude": return ("claude auth login", "claude auth logout", ["auth", "status"])
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
            let status = try? await runner.run(tool.id, auth.status, in: nil, timeout: CommandTimeout.git)
            let identity = status.flatMap { AuthStatus.identity(from: $0.stdout + "\n" + $0.stderr, tool: tool.id) }
            let signedIn = identity != nil
            return Connection(id: tool.id, name: tool.name, state: .detected,
                              label: signedIn ? (identity ?? "signed in") : "not signed in",
                              detail: signedIn ? nil : "\(tool.name) is installed but not signed in; a run would stop at its own prompt.",
                              auth: ConnectionAuth(signIn: auth.signIn, signOut: auth.signOut, identity: identity),
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
