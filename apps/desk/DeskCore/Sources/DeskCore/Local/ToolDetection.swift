import Foundation

/// Which agent CLIs are on this Mac, and the GitHub row; nothing here connects to an agent.
enum ToolDetection {
    static let tools: [(id: String, name: String)] = [("codex", "Codex"), ("claude", "Claude"), ("gemini", "Gemini")]
    static let note = "Detected on this Mac. Dev Desk doesn't connect to agents yet."

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
            return Connection(id: tool.id, name: tool.name, state: found ? .detected : .missing, label: found ? "CLI found" : "not found")
        }
    }

    static func github(_ state: GitHubState) -> Connection {
        switch state {
        case .ready: return Connection(id: "github", name: "GitHub", state: .connected, label: "connected")
        case .unavailable(let reason): return Connection(id: "github", name: "GitHub", state: .unavailable, label: reason)
        }
    }
}
