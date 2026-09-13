import Foundation
import Observation

extension ShellSessionState {
    /// Preparing counts: a start still waiting on git is a session you can stop, and one nothing should replace.
    public var isLive: Bool {
        switch self {
        case .preparing, .running: return true
        default: return false
        }
    }
}

public enum ShellSessionState: Equatable {
    /// The plan shown under the trust note; nil until one is read.
    case idle(TaskFolderPlan?)
    case preparing
    case running(TaskFolder)
    case ended(TaskFolder, status: Int32?)
    case failed(String)
}

/// What a window's sessions run: the user's shell, or the task's agent, whose plan can also be a detached worktree for a task with no branch.
public enum SessionPurpose: Equatable { case shell, agent }

/// Each task's ONE session in this window, keyed by task id — a login shell, or that shell running the task's
/// agent. Nothing runs in the repository until `start`, which only the user's click, or Auto, calls.
///
/// The purpose belongs to the session, not to the registry (ADR 0026): it decides how the folder is
/// materialised, so a task cannot hold a shell and an agent at once — which nobody wanted in one worktree, and
/// which the board could not have shown anyway.
@MainActor
@Observable
public final class ShellSessions {
    static let noFolderReason = "Sample projects have no folder, so there is no shell to start."
    static let noFolderForAgentReason = "Sample projects have no folder, so there is no agent to start."

    private var states: [String: ShellSessionState] = [:]
    private var generations: [String: Int] = [:]
    /// Called when a session ends, so what a run wrote is read back without waiting for a manual reload.
    public var onSessionEnded: ((String) -> Void)?

    /// What each live session is. Set at `start`, read by everything that distinguishes an agent from a shell.
    private var purposes: [String: SessionPurpose] = [:]
    /// The newest context reading for each session. It lives here rather than in the pane because a pane is
    /// rebuilt constantly, and a meter that starts from nothing on every redraw is a flicker, not a reading.
    private var usages: [String: ContextUsage] = [:]
    /// When each session's log was last read, so a redraw cannot turn a poll into a loop.
    @ObservationIgnored private var usageReads: [String: Date] = [:]
    @ObservationIgnored private let projectRoot: URL?
    @ObservationIgnored private let runner: CommandRunner
    /// Where this project's live sessions are written down, so the app being killed leaves a trace of them
    /// (ADR 0030). Nil for a sample, which has no folder to write in and nothing to record.
    @ObservationIgnored public let journal: RunJournal?
    /// What each live session would be called in a recovered row, since nothing else on disk knows the task's title.
    @ObservationIgnored private var titles: [String: String] = [:]

    /// A nil root, as a sample has, leaves every session failed and runs nothing.
    public init(projectRoot: URL?, runner: CommandRunner = ProcessRunner()) {
        self.projectRoot = projectRoot
        self.runner = runner
        self.journal = projectRoot.map { RunJournal(projectRoot: $0) }
    }

    /// What this task's session is, or nil when it has never started one.
    public func purpose(for taskID: String) -> SessionPurpose? { purposes[taskID] }

    public func state(for taskID: String) -> ShellSessionState {
        guard projectRoot != nil else { return .failed(Self.noFolderReason) }
        return states[taskID] ?? .idle(nil)
    }

    /// The refusal an agent start would get on a sample, which names the agent rather than a shell.
    public func startRefusal(for purpose: SessionPurpose) -> String? {
        projectRoot == nil ? (purpose == .agent ? Self.noFolderForAgentReason : Self.noFolderReason) : nil
    }

    /// Reads the folder a start would use, for the note under the trust text. A started or ended session keeps its state.
    public func refreshPlan(taskID: String, purpose: SessionPurpose = .shell, branch: String?, taskNumber: Int?,
                            noBranchNote: String? = nil, worktreeLocation: String, baseRef: String? = nil) async {
        guard let resolver = resolver(worktreeLocation), case .idle = state(for: taskID) else { return }
        let plan = await readPlan(resolver, purpose: purpose, branch: branch, taskNumber: taskNumber,
                                  noBranchNote: noBranchNote, baseRef: baseRef)
        // A refresh cancelled by a task switch may have read a stale list, and a start may have begun meanwhile.
        guard !Task.isCancelled, case .idle = state(for: taskID) else { return }
        states[taskID] = .idle(plan)
    }

    /// Plans again with the location the user has now, creates the worktree when the plan needs one, and leaves the session running there.
    /// `refusingRoot`, which Auto passes, fails the session with the note instead when the folder falls back to the project root, whether
    /// the plan said so or git refused the worktree, so nothing is launched there.
    public func start(taskID: String, purpose: SessionPurpose = .shell, branch: String?, taskNumber: Int?,
                      noBranchNote: String? = nil, worktreeLocation: String,
                      baseRef: String? = nil, refusingRoot: Bool = false) async {
        guard let resolver = resolver(worktreeLocation) else { return }
        switch state(for: taskID) {
        case .preparing, .running: return
        default: break
        }
        states[taskID] = .preparing
        purposes[taskID] = purpose
        let plan = await readPlan(resolver, purpose: purpose, branch: branch, taskNumber: taskNumber,
                                  noBranchNote: noBranchNote, baseRef: baseRef)
        let folder = await resolver.materialise(plan, for: purpose)
        // A folder with a note is the project root, where the task's own checkout should have been.
        if refusingRoot, let note = folder.note {
            states[taskID] = .failed(note)
            return
        }
        generations[taskID, default: 0] += 1
        // The previous run's reading is not this one's, and keeping it would open a fresh agent at 80%.
        usages[taskID] = nil
        usageReads[taskID] = nil
        states[taskID] = .running(folder)
    }

    /// How much context this task's agent is holding, or nil when nothing has been read for it.
    public func usage(for taskID: String) -> ContextUsage? { usages[taskID] }

    /// The gap between reads. The CLI appends to its transcript as it works, so a meter that lags a few seconds
    /// is still a meter, while anything faster re-reads a 256 KB tail for a number that has barely moved.
    public static let usageInterval: Duration = .seconds(4)
    /// The floor a caller cannot go under, whatever it asks for.
    static let usageGap: TimeInterval = 3

    /// Keeps `usage(for:)` current while the task's session runs, and returns as soon as it stops. The pane
    /// drives this from a `.task`, so closing the pane cancels it and no session nobody is watching is polled.
    public func trackUsage(taskID: String, agent: AgentKind, home: String = NSHomeDirectory()) async {
        while !Task.isCancelled {
            guard case .running = state(for: taskID) else { return }
            await refreshUsage(taskID: taskID, agent: agent, home: home)
            try? await Task.sleep(for: Self.usageInterval)
        }
    }

    /// One reading, taken off the main actor because it opens and reads a file. Three cases return without
    /// touching the disk: a sample project, which runs nothing and so has no session to read; a session that is
    /// not running, whose log will not change again; and a read taken seconds ago, which is still the answer.
    public func refreshUsage(taskID: String, agent: AgentKind, home: String = NSHomeDirectory()) async {
        guard projectRoot != nil, case .running(let folder) = state(for: taskID) else { return }
        let now = Date()
        if let last = usageReads[taskID], now.timeIntervalSince(last) < Self.usageGap { return }
        usageReads[taskID] = now
        let directory = folder.url.path
        let generation = generations[taskID, default: 0]
        let usage = await Task.detached(priority: .utility) {
            SessionUsageReader.usage(agent: agent, directory: directory, home: home)
        }.value
        // The session may have ended, or been restarted in another folder, while the file was read: a reading
        // belongs to the run it was taken for and to no other.
        guard let usage, generation == generations[taskID, default: 0], case .running = state(for: taskID) else { return }
        usages[taskID] = usage
    }

    /// Counts the task's moves into `.running`. The app keeps the value its process started under and hands it back to `markEnded`.
    public func generation(for taskID: String) -> Int { generations[taskID, default: 0] }

    /// The app calls this when the session's process exits, or when the user ends it. An exit from an earlier run is ignored,
    /// so a process that ends late can't end the one started after it.
    public func markEnded(taskID: String, status: Int32?, generation: Int) {
        guard generation == generations[taskID, default: 0], case .running(let folder) = states[taskID] else { return }
        states[taskID] = .ended(folder, status: status)
        onSessionEnded?(taskID)
    }

    public var runningTaskIDs: [String] {
        states.compactMap { id, state in
            if case .running = state { return id }
            return nil
        }.sorted()
    }

    /// Tasks running an agent, which is what Auto's limit counts — a shell you opened is not one of its slots.
    public var activeAgentTaskIDs: [String] {
        activeTaskIDs.filter { purposes[$0] == .agent }
    }

    /// Tasks whose session is preparing or running: a start still waiting on git already holds one of Auto's slots.
    public var activeTaskIDs: [String] {
        states.compactMap { id, state in
            switch state {
            case .preparing, .running: return id
            default: return nil
            }
        }.sorted()
    }

    /// A shell ignores the base ref; an agent plans with it, so a numbered task with no branch can get a detached worktree.
    private func readPlan(_ resolver: TaskFolderResolver, purpose: SessionPurpose, branch: String?, taskNumber: Int?,
                          noBranchNote: String?, baseRef: String?) async -> TaskFolderPlan {
        switch purpose {
        case .shell: return await resolver.plan(branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote)
        case .agent: return await resolver.planAgent(branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote, baseRef: baseRef)
        }
    }

    private func resolver(_ worktreeLocation: String) -> TaskFolderResolver? {
        projectRoot.map { TaskFolderResolver(projectRoot: $0, worktreeLocation: worktreeLocation, runner: runner) }
    }
}
