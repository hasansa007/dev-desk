import Foundation

/// What Insights needs to ask a real agent: which CLI answers, the repository it reads, and where the family is installed.
public struct InsightsAgentPlan: Hashable {
    public var agent: AgentKind
    public var repositoryRoot: String
    public var skillRoot: String

    /// The agent's display name, which the conversation labels its replies with.
    public var provider: String { AgentLaunch.displayName(agent) }

    public init(agent: AgentKind, repositoryRoot: String, skillRoot: String = AgentLaunch.skillRoot) {
        self.agent = agent
        self.repositoryRoot = repositoryRoot
        self.skillRoot = skillRoot
    }
}

/// One answer from the door: its prose, and the trailing `file:line` the bubble shows apart from it.
public struct InsightsAnswer: Hashable {
    public var text: String
    public var citation: String?
    public init(text: String, citation: String? = nil) {
        self.text = text
        self.citation = citation
    }
}

public enum InsightsAgentError: Error, Equatable, LocalizedError {
    case toolMissing(AgentKind)
    case failed(String)
    case empty(AgentKind)

    public var errorDescription: String? {
        switch self {
        case .toolMissing(let agent): return "\(AgentLaunch.displayName(agent)) is not installed, so Insights can't answer."
        case .failed(let detail): return "The agent couldn't answer: \(detail)"
        case .empty(let agent): return "\(AgentLaunch.displayName(agent)) finished without saying anything."
        }
    }
}

/// Runs the insights door headlessly and hands back what it said. ADR 0030: this one surface uses `claude -p` and
/// `codex exec`, the forms every other run deliberately avoids — a question asked in chat has no terminal to watch,
/// and the answer belongs in the bubble under it.
public struct InsightsAgent {
    /// An agent reading a repository takes minutes; CommandTimeout's entries are all sized for a git read.
    public static let timeout: TimeInterval = 300

    let runner: CommandRunner
    let plan: InsightsAgentPlan

    public init(runner: CommandRunner, plan: InsightsAgentPlan) {
        self.runner = runner
        self.plan = plan
    }

    /// The prompt form `scripts/dev.py` builds, pointed at the insights door, with the question as its argument.
    public static func prompt(skillRoot: String, question: String) -> String {
        let root = skillRoot.hasSuffix("/") ? String(skillRoot.dropLast()) : skillRoot
        return "Read \(root)/skills/insights/SKILL.md and execute it exactly as written, "
            + "following every phase and gate it defines. Arguments: \(question)"
    }

    /// The verified non-interactive forms, and the only place in the family that builds one.
    public static func arguments(agent: AgentKind, prompt: String) -> [String] {
        switch agent {
        case .claude: return ["-p", prompt]
        case .codex: return ["exec", prompt]
        }
    }

    /// The answer, read in the repository the question is about. Cancellation is rethrown, so a newer question drops this run.
    public func ask(_ question: String) async throws -> InsightsAnswer {
        let prompt = Self.prompt(skillRoot: plan.skillRoot, question: question)
        let result: CommandResult
        do {
            result = try await runner.run(plan.agent.rawValue, Self.arguments(agent: plan.agent, prompt: prompt),
                                          in: URL(fileURLWithPath: plan.repositoryRoot, isDirectory: true),
                                          timeout: Self.timeout)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw InsightsAgentError.failed(error.localizedDescription)
        }
        if result.toolMissing { throw InsightsAgentError.toolMissing(plan.agent) }
        guard result.succeeded else {
            throw InsightsAgentError.failed(GitOutput.lastNonEmptyLine(result.stderr) ?? "it exited with status \(result.status)")
        }
        guard let answer = Self.answer(from: result.stdout) else { throw InsightsAgentError.empty(plan.agent) }
        return answer
    }

    /// The door cites `file:line` inside its prose, so only a trailing line that is nothing *but* a citation is lifted
    /// out of it — anything else stays where the agent put it.
    static func answer(from output: String) -> InsightsAnswer? {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        var citation: String?
        if lines.count > 1, let last = lines.last?.trimmingCharacters(in: .whitespaces), isCitation(last) {
            citation = last
            lines.removeLast()
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : InsightsAnswer(text: text, citation: citation)
    }

    private static func isCitation(_ line: String) -> Bool {
        line.range(of: "^[A-Za-z0-9_./-]+\\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?$", options: .regularExpression) != nil
    }

    /// Which detected CLI answers Insights, in the order the connections arrive. A signed-out agent is not one: a
    /// headless run has no terminal to answer its own sign-in prompt in, so it would hang rather than fail plainly.
    /// `noAgentReason` is what the panel says when no agent is installed at all.
    public static func availability(connections: [Connection], repositoryRoot: String?,
                                    skillRoot: String = AgentLaunch.skillRoot,
                                    noAgentReason: String) -> InsightsAvailability {
        let agents = connections.filter { $0.state == .detected }
            .compactMap { connection in AgentKind(rawValue: connection.id).map { (connection: connection, kind: $0) } }
        guard let ready = agents.first(where: { !$0.connection.isSignedOut }) else {
            guard let signedOut = agents.first else { return .unavailable(noAgentReason) }
            return .unavailable(signedOut.connection.detail
                ?? "\(signedOut.connection.name) is installed but not signed in, so Insights can't ask it anything.")
        }
        guard let repositoryRoot else { return .unavailable(noRepositoryReason) }
        return .live(InsightsAgentPlan(agent: ready.kind, repositoryRoot: repositoryRoot, skillRoot: skillRoot))
    }

    /// The door resolves a repository before it answers, so a folder that is not one has nothing for it to read.
    public static let noRepositoryReason = "Insights answers from a git repository, and this folder isn't one."
}
