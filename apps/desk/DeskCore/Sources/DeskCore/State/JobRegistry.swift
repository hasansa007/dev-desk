import Foundation
import Observation

/// What a background run is doing. It has no terminal, so every state it can be in has to be shown.
public enum JobState: Equatable {
    case starting
    case running
    /// Stopped needing an answer. Answering resumes the same session (ADR 0025).
    case asking(String)
    case ended(text: String, failed: Bool)

    public var isLive: Bool {
        switch self {
        case .starting, .running: return true
        case .asking, .ended: return false
        }
    }

    public var label: String {
        switch self {
        case .starting: return "Starting"
        case .running: return "Running in the background"
        case .asking: return "Waiting for your answer"
        case .ended(_, let failed): return failed ? "Ended with an error" : "Finished"
        }
    }
}

public struct BackgroundJob: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let agent: String
    public let door: String
    public let directory: String
    public var sessionID: String?
    /// Kept so answering resumes under the same grant the run was started with.
    public let permission: RunPermission
    public var state: JobState = .starting
    /// The last lines the run wrote, newest last. Capped: a run can talk for a long time and this is a row.
    public var log: [String] = []

    static let logLimit = 200
}

/// Spawns a headless run and reports its lines back. A protocol so the registry can be tested without
/// starting an agent — the thing that would otherwise make these paths untestable and therefore untested.
///
/// The callbacks are `@MainActor`: a pipe delivers on a background queue, and the hop belongs to the spawner
/// that owns the pipe. Hopping inside the registry instead made every state change land a turn later, which is
/// invisible in the app and untestable everywhere.
public protocol JobSpawner: AnyObject {
    func spawn(id: String, launch: JobLaunch, directory: String,
               onLine: @escaping @MainActor (String) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void)
    func stop(id: String)
}

/// Every background run in the app, not in a window. #67 asks that a run survive closing the project window,
/// and a per-window registry cannot: its owner is gone. The app owns this one, and ends it at quit — the same
/// bargain `endAllBeforeQuit` already makes for shells, and the reason this is not the detached shape that
/// outlives the app (ADR 0025).
@MainActor
@Observable
public final class JobRegistry {
    public private(set) var jobs: [BackgroundJob] = []
    private let spawner: JobSpawner
    private let home: String

    public init(spawner: JobSpawner, home: String = NSHomeDirectory()) {
        self.spawner = spawner
        self.home = home
    }

    public func job(_ id: String) -> BackgroundJob? { jobs.first { $0.id == id } }

    public var liveCount: Int { jobs.filter { $0.state.isLive }.count }

    /// One background run per door **per project**. The registry is the app's, so asking by door alone let a
    /// run in one project claim the button in every other window — and tell that window its own gaps were
    /// being read. Two surveys in one repo would write the same report over each other; two in different
    /// repos are two runs.
    public func hasLiveJob(door: String, in directory: String) -> Bool {
        jobs.contains { $0.door == door && $0.directory == directory && $0.state.isLive }
    }

    /// Returns nil when the family has no verified invocation for that agent, rather than guessing one.
    @discardableResult
    public func start(door: String, title: String, agent: String, arguments: [String] = [],
                      permission: RunPermission, directory: String) -> String? {
        guard let launch = JobCommand.launch(door: door, agent: agent, arguments: arguments,
                                             permission: permission, directory: directory, home: home) else { return nil }
        let id = "job:\(door):\(UUID().uuidString.prefix(8))"
        jobs.insert(BackgroundJob(id: id, title: title, agent: agent, door: door, directory: directory,
                                  sessionID: launch.sessionID, permission: permission), at: 0)
        run(id: id, launch: launch, directory: directory)
        return id
    }

    /// Answering continues the same session; a job that is not waiting on a question ignores this.
    public func answer(_ text: String, to id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), case .asking = jobs[index].state else { return }
        guard let launch = JobCommand.resume(agent: jobs[index].agent, sessionID: jobs[index].sessionID,
                                            answer: text, permission: jobs[index].permission) else { return }
        // The previous process may have written its result and not yet exited; re-spawning under the same id
        // would let its termination handler fire against the new one and mark a live run finished.
        spawner.stop(id: id)
        jobs[index].state = .starting
        append("› \(text)", to: index)
        run(id: id, launch: launch, directory: jobs[index].directory)
    }

    public func stop(_ id: String) {
        spawner.stop(id: id)
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .ended(text: "Stopped", failed: false)
    }

    public func remove(_ id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isLive else { return }
        jobs.remove(at: index)
    }

    private func run(id: String, launch: JobLaunch, directory: String) {
        spawner.spawn(id: id, launch: launch, directory: directory,
                      onLine: { [weak self] line in self?.receive(line, id: id) },
                      onExit: { [weak self] status in self?.finish(id: id, status: status) })
    }

    func receive(_ line: String, id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if case .starting = jobs[index].state { jobs[index].state = .running }
        guard let event = JobStream.event(from: line) else { return }
        switch event {
        case .session(let sessionID):
            jobs[index].sessionID = sessionID
        case .line(let text):
            append(text, to: index)
        case .ended(let text, let question):
            append(text, to: index)
            jobs[index].state = question.map { JobState.asking($0) } ?? .ended(text: text, failed: false)
        }
    }

    /// A non-zero exit that never wrote a result is still an end — otherwise a crashed run pulses forever.
    func finish(id: String, status: Int32) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if case .asking = jobs[index].state { return }
        guard jobs[index].state.isLive else { return }
        jobs[index].state = .ended(text: status == 0 ? "Finished" : "Exited with status \(status)", failed: status != 0)
    }

    private func append(_ text: String, to index: Int) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            jobs[index].log.append(String(line))
        }
        if jobs[index].log.count > BackgroundJob.logLimit {
            jobs[index].log.removeFirst(jobs[index].log.count - BackgroundJob.logLimit)
        }
    }
}
