import Foundation

/// A CLI a task can be handed to. Dev Desk types its command into the developer's OWN terminal and the session runs
/// there, out of the app's sight and followed by its branch (ADR 0036 decision 6, brought forward from step 6).
///
/// Only commands that ran for real belong here. Checked 2026-09-16: Gemini 0.60.0 (API key) and opencode 1.18.31 —
/// the build a login shell resolves, not the older one in ~/.opencode/bin — each read a repository file and the
/// family's own SKILL.md. Antigravity 1.2.1 was run by the developer rather than by this tooling, because a
/// third-party tool invoking it is exactly what its terms forbid; handing it a command to run is not.
///
/// The family lives outside the project, so a tool that fences its file tools to the workspace is given the family's
/// folder. Without `--include-directories`, a headless Gemini asked to read SKILL.md waited five minutes and printed
/// nothing.
public enum HandoffAgent: String, CaseIterable, Hashable {
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

    /// The line typed into the terminal. Every form stays interactive, so the pipeline's gates are answered there.
    public func command(prompt: String, familyRoot: String) -> String {
        let prompt = DoorCommand.quoted(prompt), root = DoorCommand.quoted(familyRoot)
        switch self {
        case .gemini: return "gemini --include-directories \(root) -i \(prompt)"
        case .opencode: return "opencode --prompt \(prompt)"
        case .antigravity: return "agy --add-dir \(root) -i \(prompt)"
        }
    }

    /// The installed ones, in declaration order, by `which` — read-only, nothing is launched. An absent tool is not
    /// offered at all: a hand-off row with nothing behind it is the kind of claim ADR 0036 exists to stop.
    public static func detect(runner: CommandRunner) async -> [HandoffAgent] {
        let found = await allCases.concurrentMap { agent -> (HandoffAgent, Bool) in
            let result = try? await runner.run("which", [agent.executable], in: nil, timeout: CommandTimeout.git)
            return (agent, result?.succeeded ?? false)
        }
        return found.filter { $0.1 }.map { $0.0 }
    }
}
