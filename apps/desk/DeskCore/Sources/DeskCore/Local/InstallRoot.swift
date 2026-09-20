import Foundation

/// Where the dev family is installed, for every path this app hands an agent. One authority, because the
/// literal it replaces lived in six places and only `scripts/dev.py` was updated when the root moved:
/// ADR 0054 made Claude Code's root a hidden symlink both installs maintain, since a PLUGIN install creates
/// no `~/.claude/skills/dev` at all — so every prompt Dev Desk built named a path that did not exist.
/// Mirrors `ROOTS`, `FALLBACKS` and `skill_root` in `scripts/dev.py`.
public enum InstallRoot {
    /// Relative to home throughout: `DoorCommand.doorPath` joins it with the home it was given, and only
    /// `AgentLaunch.skillRoot` expands it, so a test can resolve either against a home that is not this machine's.
    public static let claude = ".claude/.dev-root"
    public static let codex = ".codex/skills/dev"

    /// The per-CLI link a symlink install still writes, for a machine installed before 0054. Codex has none:
    /// 0054 moved Claude Code's root, and `~/.codex/skills/dev` is still where install.sh puts Codex's copy.
    static let fallbacks = [claude: ".claude/skills/dev"]

    /// The declared root when it is installed, else its pre-0054 fallback when THAT is. Neither present returns
    /// the declared root rather than nil, as `skill_root` does: a family that is not installed should report the
    /// path it belongs at, which is a readable failure, where an empty string is not.
    public static func resolve(_ root: String, home: String,
                               exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        if exists("\(home)/\(root)") { return root }
        guard let fallback = fallbacks[root], exists("\(home)/\(fallback)") else { return root }
        return fallback
    }
}
