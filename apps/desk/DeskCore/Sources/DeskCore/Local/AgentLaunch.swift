import Foundation

/// The agents Dev Desk starts. Gemini has no confirmed way to run the dev pipeline, so it has no case.
public enum AgentKind: String, Equatable {
    case claude, codex
}

/// Builds `dev run`'s command for a task's agent. It only builds; the app runs it in the task's folder, through the user's login shell.
public enum AgentLaunch {
    /// "Claude" → .claude and "Codex" → .codex, by ToolDetection's names; nil for Gemini and anything else.
    public static func agent(forConnectionName name: String) -> AgentKind? {
        ToolDetection.tools.first { $0.name == name }.flatMap { AgentKind(rawValue: $0.id) }
    }

    /// `build_prompt` in scripts/dev.py, byte for byte. ` Arguments: #N` names the task only while it has no branch, since nothing else does then.
    public static func prompt(skillRoot: String, taskNumber: Int?, hasBranch: Bool) -> String {
        // os.path.join adds a separator only when the root doesn't already end in one.
        let door = skillRoot.isEmpty || skillRoot.hasSuffix("/") ? skillRoot + "SKILL.md" : skillRoot + "/SKILL.md"
        let extra = hasBranch ? "" : taskNumber.map { " Arguments: #\($0)" } ?? ""
        return "Read \(door) and execute it exactly as written, following every phase and gate it defines.\(extra)"
    }

    /// Always interactive: the agent's name and the prompt, never -p, exec, a model, or a flag that skips approvals.
    public static func arguments(agent: AgentKind, prompt: String) -> [String] {
        [agent.rawValue, prompt]
    }

    /// Where the dev skill is installed, as `skill_root()` in scripts/dev.py has it.
    public static var skillRoot: String {
        NSString(string: "~/.claude/skills/dev").expandingTildeInPath
    }

    public static func displayName(_ agent: AgentKind) -> String {
        switch agent {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
