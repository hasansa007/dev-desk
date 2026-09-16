import Foundation

/// The agents Dev Desk starts. Gemini has no confirmed way to run the dev pipeline, so it has no case.
public enum AgentKind: String, Equatable, CaseIterable {
    case claude, codex
}

/// Builds `dev run`'s command for a task's agent. It only builds; the app runs it in the task's folder, through the user's login shell.
public enum AgentLaunch {
    /// "Claude" → .claude and "Codex" → .codex, by ToolDetection's names; nil for Gemini and anything else.
    public static func agent(forConnectionName name: String) -> AgentKind? {
        ToolDetection.tools.first { $0.name == name }.flatMap { AgentKind(rawValue: $0.id) }
    }

    /// `build_prompt` in scripts/dev.py, byte for byte. ` Arguments: #N` names the task only while it has no branch, since nothing else does then.
    /// Delegate appends `DoorCommand.delegationInstruction` after the arguments clause — the same paragraph a door agent gets — so a task
    /// agent and a door agent are asked for the same thing in the same words; Standard stays the byte-for-byte prompt.
    public static func prompt(skillRoot: String, taskNumber: Int?, hasBranch: Bool, mode: RunMode = .standard) -> String {
        // os.path.join adds a separator only when the root doesn't already end in one.
        let door = skillRoot.isEmpty || skillRoot.hasSuffix("/") ? skillRoot + "SKILL.md" : skillRoot + "/SKILL.md"
        let extra = hasBranch ? "" : taskNumber.map { " Arguments: #\($0)" } ?? ""
        let delegation = mode == .delegate ? " \(DoorCommand.delegationInstruction)" : ""
        return "Read \(door) and execute it exactly as written, following every phase and gate it defines.\(extra)\(delegation)"
    }

    /// Always interactive: the agent's name and the prompt, never -p, exec, a model, or a flag that skips approvals.
    public static func arguments(agent: AgentKind, prompt: String) -> [String] {
        [agent.rawValue, prompt]
    }

    /// Where the family is installed for this agent, as `skill_root(agent)` in scripts/dev.py has it.
    /// install.sh writes one copy per agent, and an agent can only read its own: pointing Codex at
    /// `~/.claude/skills/dev` asks it to read a door it may not have.
    public static func skillRoot(for agent: AgentKind) -> String {
        NSString(string: "~/.\(agent.rawValue)/skills/dev").expandingTildeInPath
    }

    /// The agents a Start may offer, in the order the sheet lists them. Gemini is not one: it has no case,
    /// because the family has no verified way to run the pipeline with it.
    public static let runnableKinds: [AgentKind] = AgentKind.allCases

    /// The name a connection and `DoorCommand` know this agent by — "Claude", not the longer display name.
    /// The inverse of `agent(forConnectionName:)`, and the string every start path passes around.
    public static func connectionName(_ agent: AgentKind) -> String {
        DoorCommand.agents.first { $0.executable == agent.rawValue }?.name ?? agent.rawValue
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
