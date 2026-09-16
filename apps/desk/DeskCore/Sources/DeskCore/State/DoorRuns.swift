import Foundation
import Observation

/// One door started for this project: what it is, and the exact command typed into its shell.
public struct DoorRun: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var agent: String
    public var command: String
    /// Passed to the folder rule, so the shell's note says why a run opens at the project root.
    public var folderNote: String
    /// True for a report door: its shell opens, then moves into a fresh worktree on origin's base before the command.
    public var freshBase: Bool

    public init(id: String, title: String, agent: String, command: String, folderNote: String, freshBase: Bool = false) {
        self.id = id
        self.freshBase = freshBase
        self.title = title
        self.agent = agent
        self.command = command
        self.folderNote = folderNote
    }
}

/// The runs this window has started, newest first. Their state lives in `ShellSessions`, keyed by the same id.
@MainActor
@Observable
public final class DoorRuns {
    public private(set) var runs: [DoorRun] = []
    public var selectedID: String?

    public init() {}

    /// Replaces a run with the same id, so starting Findings twice never leaves two rows for one shell.
    public func add(_ run: DoorRun) {
        runs.removeAll { $0.id == run.id }
        runs.insert(run, at: 0)
        selectedID = run.id
    }

    public func remove(_ id: String) {
        runs.removeAll { $0.id == id }
        if selectedID == id { selectedID = runs.first?.id }
    }

    public func run(_ id: String) -> DoorRun? { runs.first { $0.id == id } }

    /// One id shape the whole app agrees on, so a card, a run row and a shell all mean the same session.
    public static func id(door: String) -> String { "door:\(door)" }
    /// A findings run is identified by the half of the report it writes, not by its door: a defects run and an
    /// architecture run are two runs, two rows and two shells, while the same half twice is one run asked
    /// for twice — which `prepareRun` then refuses on the id alone.
    public static func id(door: String, scope: FindingsRunScope) -> String { "door:\(door):\(scope.rawValue)" }
    public static func id(task number: Int) -> String { "task:\(number)" }
    /// A run for work that exists only in `docs/backlog/`, which has no number to name it by.
    public static func id(local entry: String) -> String { "local:\(entry)" }

    /// The id a task's `/dev` start runs under, by the one rule: a local entry names itself, an issue names
    /// its number. nil for a card `/dev` has nothing to open. Here so the Start, the queue and the parked
    /// launch cannot disagree about which run a card is.
    public static func id(for task: DeskTask) -> String? {
        if let entry = task.localBacklogID { return id(local: entry) }
        return task.taskNumber.map { id(task: $0) }
    }
}

/// Builds what a door is started with: the prompt form `scripts/dev.py` builds, so one string works in either CLI.
public enum DoorCommand {
    /// Display name, executable, and the path install.sh links the family to for that CLI.
    public static let agents: [(name: String, executable: String, root: String)] = [
        ("Claude", "claude", ".claude/skills/dev"),
        ("Codex", "codex", ".codex/skills/dev"),
    ]

    /// Terminal runs only. Their root is Claude's: install.sh writes the family for Claude and Codex alone, and these
    /// read it from there (verified 2026-09-16).
    public static let terminalOnlyAgents: [(name: String, executable: String, root: String)] = [
        ("Gemini", "gemini", ".claude/skills/dev"),
        ("opencode", "opencode", ".claude/skills/dev"),
        ("Antigravity", "agy", ".claude/skills/dev"),
    ]

    /// Any agent a door or task may run with in a terminal.
    public static func agent(named name: String) -> (name: String, executable: String, root: String)? {
        (agents + terminalOnlyAgents).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Only an agent a background run can use: a headless form whose output this app reads — Claude and Codex.
    public static func backgroundAgent(named name: String) -> (name: String, executable: String, root: String)? {
        agents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// `dev` is the family's root SKILL.md; every other door is `skills/<door>/SKILL.md` beneath the same root.
    public static func doorPath(_ door: String, root: String, home: String) -> String {
        let base = "\(home)/\(root)"
        return door == "dev" ? "\(base)/SKILL.md" : "\(base)/skills/\(door)/SKILL.md"
    }

    /// The prompt itself, shared by the command typed into a terminal and the argv a background run is spawned with.
    /// Standard mode is the prompt `scripts/dev.py` builds, byte for byte; Delegate appends to it rather than
    /// rewording it, so the door is still read and followed exactly as written, and only the way its steps are
    /// carried out changes.
    public static func prompt(door: String, agent name: String, arguments: [String] = [], home: String,
                              mode: RunMode = .standard) -> String? {
        guard let agent = agent(named: name) else { return nil }
        let extra = arguments.isEmpty ? "" : " Arguments: \(arguments.joined(separator: " "))"
        let delegation = mode == .delegate ? " \(delegationInstruction)" : ""
        return "Read \(doorPath(door, root: agent.root, home: home)) and execute it exactly as written, "
            + "following every phase and gate it defines.\(extra)\(delegation)"
    }

    /// What Delegate asks of the agent, in the terms the doors already use. The gates stay the agent's own to
    /// hold: a worker finishes a brief, and the orchestrator decides whether that brief passed. Small edits are
    /// exempt because a brief for a one-line change costs more than the change.
    public static let delegationInstruction =
        "Run this door as an orchestrator: delegate each self-contained implementation step to a worker subagent "
        + "with a brief it can finish alone, review what comes back against the door's own gates before accepting "
        + "it, and edit directly only where delegating would cost more than the change."

    /// nil for a CLI the family has no verified invocation for. `arguments` are the door's own, such as `--perf`.
    public static func build(door: String, agent name: String, arguments: [String] = [], home: String,
                             mode: RunMode = .standard) -> String? {
        guard let agent = agent(named: name),
              let prompt = prompt(door: door, agent: name, arguments: arguments, home: home, mode: mode) else { return nil }
        if let terminal = AgentLaunch.agent(forConnectionName: agent.name)?.terminalAgent {
            return terminal.command(prompt: prompt, familyRoot: "\(home)/\(agent.root)")
        }
        return "\(agent.executable) \(quoted(prompt))"
    }

    /// Single quotes have no escape inside them, so a quote is closed, escaped and reopened; nothing a door's arguments carry can end the string.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
