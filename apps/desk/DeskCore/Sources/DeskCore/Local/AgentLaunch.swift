import Foundation

/// The agents Dev Desk starts. Claude and Codex run in a terminal and headless in the background. Gemini, opencode
/// and Antigravity run in a terminal only, through the commands `TerminalAgent` verified: none has a headless form
/// whose output this app reads, and reading Antigravity's is what its terms forbid (ADR 0036 amendments 1 and 2).
public enum AgentKind: String, Equatable, CaseIterable {
    case claude, codex, gemini, opencode, antigravity

    /// Whether a background run — Findings or Ideation in the background, filing, a diagram — can use this agent.
    public var runsInBackground: Bool { self == .claude || self == .codex }

    /// The verified terminal command for an agent with no headless form; nil for Claude and Codex.
    public var terminalAgent: TerminalAgent? { TerminalAgent(rawValue: rawValue) }
}

/// Builds `dev run`'s command for a task's agent. It only builds; the app runs it in the task's folder, through the user's login shell.
public enum AgentLaunch {
    /// "Claude" → .claude, "Gemini" → .gemini: the inverse of `connectionName`; nil for anything else.
    public static func agent(forConnectionName name: String) -> AgentKind? {
        AgentKind.allCases.first { connectionName($0) == name }
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

    /// Always interactive: never -p, exec, a model, or a flag that skips approvals. Claude and Codex take the prompt
    /// as their argument; the other three take the verified form `TerminalAgent` holds.
    public static func arguments(agent: AgentKind, prompt: String) -> [String] {
        if let terminal = agent.terminalAgent { return terminal.arguments(prompt: prompt, familyRoot: skillRoot(for: agent)) }
        return [agent.rawValue, prompt]
    }

    /// Where the family is installed for this agent, as `skill_root(agent)` in scripts/dev.py has it.
    /// install.sh writes one copy per agent, and an agent can only read its own: pointing Codex at
    /// `~/.claude/skills/dev` asks it to read a door it may not have.
    /// install.sh writes no copy for Gemini, opencode or Antigravity, so they read Claude's — the path each was
    /// verified reading on 2026-09-16.
    public static func skillRoot(for agent: AgentKind) -> String {
        let owner = agent.runsInBackground ? agent.rawValue : AgentKind.claude.rawValue
        return NSString(string: "~/.\(owner)/skills/dev").expandingTildeInPath
    }

    /// The agents a Start may offer, in the order the sheet lists them.
    public static let runnableKinds: [AgentKind] = AgentKind.allCases

    /// The name a connection, a preference and `DoorCommand` know this agent by — "Claude", not the display name.
    /// The inverse of `agent(forConnectionName:)`, and the string every start path passes around.
    public static func connectionName(_ agent: AgentKind) -> String {
        switch agent {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "opencode"
        case .antigravity: return "Antigravity"
        }
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "opencode"
        case .antigravity: return "Antigravity"
        }
    }
}
