import Foundation
import Observation

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

/// Each task's shell, or each task's agent, in one window, keyed by task id. Nothing runs in the repository until `start`, which only the
/// user's click, or Auto for an agent, calls.
@MainActor
@Observable
public final class ShellSessions {
    static let noFolderReason = "Sample projects have no folder, so there is no shell to start."
    static let noFolderForAgentReason = "Sample projects have no folder, so there is no agent to start."

    private var states: [String: ShellSessionState] = [:]
    private var generations: [String: Int] = [:]

    @ObservationIgnored let purpose: SessionPurpose
    @ObservationIgnored private let projectRoot: URL?
    @ObservationIgnored private let runner: CommandRunner

    /// A nil root, as a sample has, leaves every session failed and runs nothing.
    public init(projectRoot: URL?, purpose: SessionPurpose = .shell, runner: CommandRunner = ProcessRunner()) {
        self.projectRoot = projectRoot
        self.purpose = purpose
        self.runner = runner
    }

    public func state(for taskID: String) -> ShellSessionState {
        guard projectRoot != nil else { return .failed(purpose == .agent ? Self.noFolderForAgentReason : Self.noFolderReason) }
        return states[taskID] ?? .idle(nil)
    }

    /// Reads the folder a start would use, for the note under the trust text. A started or ended session keeps its state.
    public func refreshPlan(taskID: String, branch: String?, taskNumber: Int?, noBranchNote: String? = nil, worktreeLocation: String,
                            baseRef: String? = nil) async {
        guard let resolver = resolver(worktreeLocation), case .idle = state(for: taskID) else { return }
        let plan = await readPlan(resolver, branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote, baseRef: baseRef)
        // A refresh cancelled by a task switch may have read a stale list, and a start may have begun meanwhile.
        guard !Task.isCancelled, case .idle = state(for: taskID) else { return }
        states[taskID] = .idle(plan)
    }

    /// Plans again with the location the user has now, creates the worktree when the plan needs one, and leaves the session running there.
    public func start(taskID: String, branch: String?, taskNumber: Int?, noBranchNote: String? = nil, worktreeLocation: String,
                      baseRef: String? = nil) async {
        guard let resolver = resolver(worktreeLocation) else { return }
        switch state(for: taskID) {
        case .preparing, .running: return
        default: break
        }
        states[taskID] = .preparing
        let plan = await readPlan(resolver, branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote, baseRef: baseRef)
        let folder = await resolver.materialise(plan)
        generations[taskID, default: 0] += 1
        states[taskID] = .running(folder)
    }

    /// Counts the task's moves into `.running`. The app keeps the value its process started under and hands it back to `markEnded`.
    public func generation(for taskID: String) -> Int { generations[taskID, default: 0] }

    /// The app calls this when the session's process exits, or when the user ends it. An exit from an earlier run is ignored,
    /// so a process that ends late can't end the one started after it.
    public func markEnded(taskID: String, status: Int32?, generation: Int) {
        guard generation == generations[taskID, default: 0], case .running(let folder) = states[taskID] else { return }
        states[taskID] = .ended(folder, status: status)
    }

    public var runningTaskIDs: [String] {
        states.compactMap { id, state in
            if case .running = state { return id }
            return nil
        }.sorted()
    }

    /// A shell ignores the base ref; an agent plans with it, so a numbered task with no branch can get a detached worktree.
    private func readPlan(_ resolver: TaskFolderResolver, branch: String?, taskNumber: Int?, noBranchNote: String?, baseRef: String?) async -> TaskFolderPlan {
        switch purpose {
        case .shell: return await resolver.plan(branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote)
        case .agent: return await resolver.planAgent(branch: branch, taskNumber: taskNumber, noBranchNote: noBranchNote, baseRef: baseRef)
        }
    }

    private func resolver(_ worktreeLocation: String) -> TaskFolderResolver? {
        projectRoot.map { TaskFolderResolver(projectRoot: $0, worktreeLocation: worktreeLocation, runner: runner) }
    }
}
