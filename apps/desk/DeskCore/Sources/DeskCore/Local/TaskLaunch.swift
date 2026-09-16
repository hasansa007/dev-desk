import Foundation

/// Everything needed to start one task, decided once and never re-derived (ADR 0036 decision 1).
///
/// It holds decisions, not derived git state. The worktree plan is deliberately absent: `TaskFolderResolver.plan`
/// reads `git worktree list`, so a plan pinned when a card was queued can be wrong by the time a slot frees;
/// the location it is resolved against is a preference, and that is what goes stale wrongly today. Everything
/// here survives the queue, so a card queued under Codex in Delegate starts under Codex in Delegate however
/// the preferences have moved since.
public struct TaskLaunch: Codable, Hashable, Identifiable {
    /// The run's id, which is also the session key: `DoorRuns.id(task:)`, `id(local:)` or `id(door:)`.
    public let id: String
    /// `DeskTask.ID`, or nil for a door run that belongs to no card.
    public let task: String?
    public let title: String
    /// The door to read: `dev` is the family root, anything else is `skills/<door>/SKILL.md` beneath it.
    public let door: String
    /// The door's own arguments, already in the shape `dev.py` expects: `["#212"]`, `["--perf"]`.
    public let arguments: [String]
    public let agent: AgentKind
    public let mode: RunMode
    /// Where a new worktree may be created, as `PreferenceKey.worktreeLocation` had it when the launch was built.
    public let worktreeLocation: String
    /// The base this task is cut from, pinned at build time. nil when git could not name one.
    public let base: LaunchBase?
    public let createdAt: Date

    public init(id: String, task: String?, title: String, door: String, arguments: [String] = [],
                agent: AgentKind, mode: RunMode = .standard, worktreeLocation: String,
                base: LaunchBase? = nil, createdAt: Date = Date()) {
        self.id = id
        self.task = task
        self.title = title
        self.door = door
        self.arguments = arguments
        self.agent = agent
        self.mode = mode
        self.worktreeLocation = worktreeLocation
        self.base = base
        self.createdAt = createdAt
    }

    /// The one prompt builder. `DoorCommand` resolves the skill root per agent — `.claude/skills/dev` against
    /// `.codex/skills/dev` — which is why this supersedes `AgentLaunch.prompt`, whose root was Claude's for
    /// both CLIs. nil only for an agent `DoorCommand` does not know.
    public func prompt(home: String) -> String? {
        DoorCommand.prompt(door: door, agent: agent.rawValue, arguments: arguments, home: home, mode: mode)
    }

    /// The shell line this launch runs as, for a hand-off that types a command or for *Copy the resume command*.
    public func command(home: String) -> String? {
        DoorCommand.build(door: door, agent: agent.rawValue, arguments: arguments, home: home, mode: mode)
    }
}

/// A base ref with the commit it pointed at when the launch was built. The ref alone is a moving target:
/// `origin/main` is whatever it is at spawn time, so two runs of one launch can sit on different code and
/// nothing records which. Both halves already exist in `GitFacts`; pinning them together is what is new.
public struct LaunchBase: Codable, Hashable {
    public let ref: String
    public let short: String?

    public init(ref: String, short: String?) {
        self.ref = ref
        self.short = short
    }

    /// `origin/main@8c1f2a0`, the form the board already prints.
    public var display: String { short.map { "\(ref)@\($0)" } ?? ref }
}

extension AgentKind: Codable {}
extension RunMode: Codable {}
