import Foundation

/// Continuing a CLI's own conversation after Dev Desk lost the session it was in. The app keeps no transcript
/// (ADR 0031): each CLI stores its own, so the only honest resume is that CLI's command, run in the same folder.
public enum AgentResume {
    /// Verified 2026-09-20 against the installed CLIs: `codex resume --last` and `claude --continue` each
    /// continue the newest conversation in the current directory. Nil for a plain shell, and for a CLI with no
    /// resume of its own — there the session starts fresh rather than pretending otherwise.
    public static func command(for executable: String?) -> (name: String, line: String)? {
        switch executable.flatMap(AgentKind.init(rawValue:)) {
        case .codex: return ("Codex", "codex resume --last")
        case .claude: return ("Claude", "claude --continue")
        default: return nil
        }
    }
}
