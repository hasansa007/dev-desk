import Foundation

/// A CLI besides Claude and Codex that can run a task's `/dev` in Dev Desk's built-in terminal: the app types its
/// command into a session in Sessions, exactly as it does for Claude and Codex, so the run is counted against the slot
/// limit and watched where every other run is. ADR 0036 amendment 2 keeps that terminal until ACP sessions exist.
///
/// Only commands that ran for real belong here. Checked 2026-09-16: Gemini 0.60.0 (API key) and opencode 1.18.31 —
/// the build a login shell resolves, not the older one in ~/.opencode/bin — each ran this exact command in a terminal
/// against a clone of this repository, read the family's SKILL.md and answered from it. Antigravity 1.2.1 was run by
/// the developer rather than by this tooling, because a third-party tool invoking it is what its terms forbid; typing
/// its own binary's command into a terminal is not, since `agy` holds its credential and the app never touches it.
///
/// The family lives outside the project, so a tool that fences its file tools to the workspace is given the family's
/// folder. Without `--include-directories`, a headless Gemini asked to read SKILL.md waited five minutes and printed
/// nothing.
public enum TerminalAgent: String, CaseIterable, Hashable {
    case gemini, opencode, antigravity

    public var name: String {
        switch self {
        case .gemini: return "Gemini"
        case .opencode: return "opencode"
        case .antigravity: return "Antigravity"
        }
    }

    public var executable: String {
        switch self {
        case .gemini: return "gemini"
        case .opencode: return "opencode"
        case .antigravity: return "agy"
        }
    }

    /// The argv, for a session started with arguments. Every form stays interactive, so the pipeline's gates are
    /// answered in the terminal.
    public func arguments(prompt: String, familyRoot: String) -> [String] {
        switch self {
        case .gemini: return ["gemini", "--include-directories", familyRoot, "-i", prompt]
        case .opencode: return ["opencode", "--prompt", prompt]
        case .antigravity: return ["agy", "--add-dir", familyRoot, "-i", prompt]
        }
    }

    /// The line typed into a shell: the argv with every value quoted, flags left bare.
    public func command(prompt: String, familyRoot: String) -> String {
        arguments(prompt: prompt, familyRoot: familyRoot).enumerated()
            .map { index, part in index == 0 || part.hasPrefix("-") ? part : DoorCommand.quoted(part) }
            .joined(separator: " ")
    }

    /// The installed ones, in declaration order, by `which` — read-only, nothing is launched. An absent tool is not
    /// offered at all: a row with nothing behind it is the kind of claim ADR 0036 exists to stop.
    public static func detect(runner: CommandRunner) async -> [TerminalAgent] {
        let found = await allCases.concurrentMap { agent -> (TerminalAgent, Bool) in
            let result = try? await runner.run("which", [agent.executable], in: nil, timeout: CommandTimeout.git)
            return (agent, result?.succeeded ?? false)
        }
        return found.filter { $0.1 }.map { $0.0 }
    }
}
