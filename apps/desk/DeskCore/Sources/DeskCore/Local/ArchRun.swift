import Foundation

/// How the Diagrams screen runs `dev:arch` for one kind, headlessly, so it exits when the diagram is written
/// and the app can fetch the new HTML. Separate from `DoorCommand`, which builds the interactive terminal
/// command: this door is the one screen that wants the run to finish on its own (there is a file to pick up
/// afterwards), so it needs the non-interactive `exec`/`-p` form and a way to know it ended.
public enum ArchRun {
    /// The `dev:arch` prompt for one kind, with an optional target. The door reads what to draw first and a
    /// bare type token after it, so a target leads and the type follows; an empty target draws the whole
    /// project. Built from the same skill path `DoorCommand` uses, so both doors read the same SKILL.md.
    public static func prompt(agent name: String, kind: String, target: String, home: String) -> String? {
        guard DoorCommand.backgroundAgent(named: name) != nil else { return nil }
        var arguments: [String] = []
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { arguments.append(trimmed) }
        arguments.append(kind)
        return DoorCommand.prompt(door: "arch", agent: name, arguments: arguments, home: home)
    }

    /// The argv a headless `dev:arch` run execs — each word its own element, never shell-quoted into a string,
    /// built through `HeadlessArgv` so the prompt sits where no flag can consume it. Verified against the
    /// installed CLIs (codex-cli 0.154.0, Claude Code 2.1.272): `codex exec -s workspace-write` runs once and
    /// exits in a sandbox that may write the repo, and `claude -p` does the same with `--permission-mode
    /// acceptEdits` and `--allowedTools` standing in for the approvals nobody is present to give.
    /// `--allowedTools` is variadic: a positional prompt after it is consumed as another tool name, and the
    /// CLI then exits 1 with "Input must be provided either through stdin or as a prompt argument when using
    /// --print" — so claude's prompt goes immediately after `-p`, before the flags (verified 2026-09-15
    /// against the installed claude at `~/.local/bin/claude`, 2.1.272). Codex's `-s` takes exactly one value,
    /// so its prompt stays the single final element. nil for a CLI this family has no verified invocation for.
    public static func launch(agent name: String, kind: String, target: String, home: String) -> [String]? {
        guard let agent = DoorCommand.backgroundAgent(named: name),
              let prompt = prompt(agent: name, kind: kind, target: target, home: home) else { return nil }
        switch agent.executable {
        case "codex":
            return HeadlessArgv.argv(head: ["codex", "exec"], flags: ["-s", "workspace-write"], prompt: prompt)
        case "claude":
            return HeadlessArgv.argv(head: ["claude", "-p"],
                                     flags: ["--permission-mode", "acceptEdits",
                                             "--allowedTools", "Bash Read Write Edit Glob Grep"],
                                     prompt: prompt)
        default:
            return nil
        }
    }
}
