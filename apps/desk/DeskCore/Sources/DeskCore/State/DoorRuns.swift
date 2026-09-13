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

    public init(id: String, title: String, agent: String, command: String, folderNote: String) {
        self.id = id
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

    /// Replaces a run with the same id, so starting Survey twice never leaves two rows for one shell.
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
    public static func id(task number: Int) -> String { "task:\(number)" }
    /// A run for work that exists only in `docs/backlog/`, which has no number to name it by.
    public static func id(local entry: String) -> String { "local:\(entry)" }
}

/// Builds what a door is started with: the prompt form `scripts/dev.py` builds, so one string works in either CLI.
public enum DoorCommand {
    /// Display name, executable, and the path install.sh links the family to for that CLI.
    public static let agents: [(name: String, executable: String, root: String)] = [
        ("Claude", "claude", ".claude/skills/dev"),
        ("Codex", "codex", ".codex/skills/dev"),
    ]

    public static func agent(named name: String) -> (name: String, executable: String, root: String)? {
        agents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// `dev` is the family's root SKILL.md; every other door is `skills/<door>/SKILL.md` beneath the same root.
    public static func doorPath(_ door: String, root: String, home: String) -> String {
        let base = "\(home)/\(root)"
        return door == "dev" ? "\(base)/SKILL.md" : "\(base)/skills/\(door)/SKILL.md"
    }

    /// The prompt itself, shared by the command typed into a terminal and the argv a background run is spawned with.
    public static func prompt(door: String, agent name: String, arguments: [String] = [], home: String) -> String? {
        guard let agent = agent(named: name) else { return nil }
        let extra = arguments.isEmpty ? "" : " Arguments: \(arguments.joined(separator: " "))"
        return "Read \(doorPath(door, root: agent.root, home: home)) and execute it exactly as written, "
            + "following every phase and gate it defines.\(extra)"
    }

    /// nil for a CLI the family has no verified invocation for. `arguments` are the door's own, such as `--perf`.
    public static func build(door: String, agent name: String, arguments: [String] = [], home: String) -> String? {
        guard let agent = agent(named: name),
              let prompt = prompt(door: door, agent: name, arguments: arguments, home: home) else { return nil }
        return "\(agent.executable) \(quoted(prompt))"
    }

    /// Single quotes have no escape inside them, so a quote is closed, escaped and reopened; nothing a door's arguments carry can end the string.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
