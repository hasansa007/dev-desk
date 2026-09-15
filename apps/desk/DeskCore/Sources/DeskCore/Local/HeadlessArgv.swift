import Foundation

/// Where the prompt goes in a headless CLI argv, decided in one place.
///
/// `claude`'s variadic flags (`<tools...>` in its help) consume every following argument up to the next flag —
/// including a trailing positional prompt, which is then read as one more of the flag's values. `claude -p
/// --permission-mode acceptEdits --allowedTools "Bash Read …" <prompt>` runs nothing: the prompt is eaten and
/// the CLI exits 1 with "Input must be provided either through stdin or as a prompt argument when using
/// --print"; the same prompt placed before the flags runs (both verified 2026-09-15 against the installed
/// claude at `~/.local/bin/claude`, Claude Code 2.1.272). Every headless launcher builds its argv through
/// `argv(head:flags:prompt:)`, so a flag added later cannot reopen the hole: the moment a variadic flag is
/// among the flags, the prompt moves in front of them, where nothing can consume it.
public enum HeadlessArgv {
    /// Every flag of the two CLIs that takes more than one value. From `claude --help` (Claude Code 2.1.272,
    /// 2026-09-15): `--add-dir <directories...>`, `--allowedTools`/`--allowed-tools <tools...>`,
    /// `--betas <betas...>`, `--disallowedTools`/`--disallowed-tools <tools...>`, `--file <specs...>`,
    /// `--mcp-config <configs...>`, `--tools <tools...>`. From `codex exec --help` (codex-cli 0.154.0):
    /// `-i, --image <FILE>...`; every other codex option takes exactly one value. Over-matching is safe — a
    /// prompt moved in front of the flags is never eaten — so a spelling one CLI shares with a one-value flag
    /// of the other (codex's `--add-dir <DIR>`) stays listed rather than being special-cased per CLI.
    public static let variadicFlags: Set<String> = [
        "--add-dir",
        "--allowedTools", "--allowed-tools",
        "--betas",
        "--disallowedTools", "--disallowed-tools",
        "--file",
        "--mcp-config",
        "--tools",
        "-i", "--image",
    ]

    /// The launch argv: `head` (the command words up to and including the subcommand or `-p`), then the flags,
    /// then the prompt as the single final element — the shape every verified invocation has — unless a
    /// variadic flag is among the flags, in which case the prompt goes immediately after `head`, before every
    /// flag, so no flag can swallow it. Each element stays its own argv word, never shell-quoted into a string.
    public static func argv(head: [String], flags: [String], prompt: String) -> [String] {
        flags.contains(where: variadicFlags.contains) ? head + [prompt] + flags : head + flags + [prompt]
    }
}
