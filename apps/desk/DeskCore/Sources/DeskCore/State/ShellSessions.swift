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

/// Each task's shell in one window, keyed by task id. Nothing runs in the repository until `start`, which only the user's click calls.
@MainActor
@Observable
public final class ShellSessions {
    static let noFolderReason = "Sample projects have no folder, so there is no shell to start."

    private var states: [String: ShellSessionState] = [:]

    @ObservationIgnored private let projectRoot: URL?
    @ObservationIgnored private let runner: CommandRunner

    /// A nil root, as a sample has, leaves every session failed and runs nothing.
    public init(projectRoot: URL?, runner: CommandRunner = ProcessRunner()) {
        self.projectRoot = projectRoot
        self.runner = runner
    }

    public func state(for taskID: String) -> ShellSessionState {
        guard projectRoot != nil else { return .failed(Self.noFolderReason) }
        return states[taskID] ?? .idle(nil)
    }

    /// Reads the folder a start would use, for the note under the trust text. A started or ended session keeps its state.
    public func refreshPlan(taskID: String, branch: String?, taskNumber: Int?, worktreeLocation: String) async {
        guard let resolver = resolver(worktreeLocation), case .idle = state(for: taskID) else { return }
        let plan = await resolver.plan(branch: branch, taskNumber: taskNumber)
        // A refresh cancelled by a task switch may have read a stale list, and a start may have begun meanwhile.
        guard !Task.isCancelled, case .idle = state(for: taskID) else { return }
        states[taskID] = .idle(plan)
    }

    /// Plans again with the location the user has now, creates the worktree when the plan needs one, and leaves the session running there.
    public func start(taskID: String, branch: String?, taskNumber: Int?, worktreeLocation: String) async {
        guard let resolver = resolver(worktreeLocation) else { return }
        switch state(for: taskID) {
        case .preparing, .running: return
        default: break
        }
        states[taskID] = .preparing
        let plan = await resolver.plan(branch: branch, taskNumber: taskNumber)
        let folder = await resolver.materialise(plan)
        states[taskID] = .running(folder)
    }

    /// The app calls this when the shell's process exits.
    public func markEnded(taskID: String, status: Int32?) {
        guard case .running(let folder) = states[taskID] else { return }
        states[taskID] = .ended(folder, status: status)
    }

    public var runningTaskIDs: [String] {
        states.compactMap { id, state in
            if case .running = state { return id }
            return nil
        }.sorted()
    }

    private func resolver(_ worktreeLocation: String) -> TaskFolderResolver? {
        projectRoot.map { TaskFolderResolver(projectRoot: $0, worktreeLocation: worktreeLocation, runner: runner) }
    }
}
