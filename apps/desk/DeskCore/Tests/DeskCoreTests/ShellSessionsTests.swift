import Foundation
import XCTest
@testable import DeskCore

/// Holds every call until `release()`, so a test can look at a session while its start is in flight.
final class HeldRunner: CommandRunner {
    private let inner: CommandRunner
    private let lock = NSLock()
    private var isReleased = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ inner: CommandRunner) { self.inner = inner }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isReleased = true
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        await withCheckedContinuation { continuation in
            let proceed = lock.withLock { () -> Bool in
                if isReleased { return true }
                held.append(continuation)
                return false
            }
            if proceed { continuation.resume() }
        }
        return try await inner.run(tool, arguments, in: directory, timeout: timeout)
    }
}

@MainActor
final class ShellSessionsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: "/work/My App", isDirectory: true)
    private static let listKey = FakeRunner.gitRead("worktree list --porcelain -z")
    private static let mainOnly = "worktree /work/My App\0HEAD \(String(repeating: "1", count: 40))\0branch refs/heads/main\0\0"
    private static let noFolder = "Sample projects have no folder, so there is no shell to start."

    private func addKey(_ path: URL) -> String { FakeRunner.gitRead("worktree add \(path.path) gh-7-demo") }

    func testAnUnseenTaskIsIdleWithoutAPlanAndRunsNothing() {
        let runner = FakeRunner()
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        XCTAssertEqual(sessions.state(for: "7"), .idle(nil))
        XCTAssertEqual(sessions.runningTaskIDs, [])
        XCTAssertEqual(runner.calls, [])
    }

    func testRefreshPlanStoresThePlanInIdle() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly)])
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .idle(.create(path: location.url.appendingPathComponent("my-app-7", isDirectory: true), branch: "gh-7-demo")))
        await sessions.refreshPlan(taskID: "14", branch: nil, taskNumber: 14, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "14"), .idle(.root(Self.root, note: "No branch for #14 yet. The shell opens at the project root; "
                                                               + "running /dev #14 there cuts gh-14-… at its first write.")))
        XCTAssertEqual(runner.keys, [Self.listKey], "only a task with a branch reads the worktree list")
    }

    func testACancelledRefreshKeepsThePlanItHad() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly)])
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        let first = ShellSessionState.idle(.create(path: location.url.appendingPathComponent("my-app-7", isDirectory: true), branch: "gh-7-demo"))
        XCTAssertEqual(sessions.state(for: "7"), first)

        // Switching tasks cancels a view's refresh; the plan it read by then may already be stale.
        try FileManager.default.createDirectory(at: location.url.appendingPathComponent("my-app-7"), withIntermediateDirectories: true)
        let refresh = Task { await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path) }
        refresh.cancel()
        await refresh.value
        XCTAssertEqual(sessions.state(for: "7"), first)
    }

    func testStartGoesFromIdleThroughPreparingToRunning() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let runner = HeldRunner(fake)
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        XCTAssertEqual(sessions.state(for: "7"), .idle(nil))

        let start = Task { await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path) }
        await waitUntil { sessions.state(for: "7") == .preparing }
        XCTAssertEqual(sessions.state(for: "7"), .preparing)
        XCTAssertEqual(sessions.runningTaskIDs, [])

        runner.release()
        await start.value
        XCTAssertEqual(sessions.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: true)))
        XCTAssertEqual(sessions.runningTaskIDs, ["7"])
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path)])
    }

    func testMarkEndedEndsTheSessionAndStartingAgainPlansAnew() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let sessions = ShellSessions(projectRoot: Self.root, runner: fake)
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        let created = TaskFolder(url: path, note: nil, created: true)
        XCTAssertEqual(sessions.state(for: "7"), .running(created))

        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .running(created), "a running session ignores another start and a refresh")
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path)])

        sessions.markEnded(taskID: "7", status: 129)
        sessions.markEnded(taskID: "8", status: 0)
        XCTAssertEqual(sessions.state(for: "7"), .ended(created, status: 129))
        XCTAssertEqual(sessions.state(for: "8"), .idle(nil), "only a running session can end")
        XCTAssertEqual(sessions.runningTaskIDs, [])

        // git now lists the worktree the first start made, so starting again opens in it instead of making another.
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        fake.script(Self.listKey, .ok(Self.mainOnly + "worktree \(path.path)\0HEAD \(String(repeating: "2", count: 40))\0branch refs/heads/gh-7-demo\0\0"))
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: false)))
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path), Self.listKey])
    }

    func testASampleSessionFailsWithItsReasonAndNeverRunsACommand() async {
        let runner = FakeRunner()
        let sessions = ShellSessions(projectRoot: nil, runner: runner)
        await sessions.refreshPlan(taskID: "42", branch: "fix/42-course-scroll", taskNumber: 42, worktreeLocation: "~/.devdesk/wt")
        await sessions.start(taskID: "42", branch: "fix/42-course-scroll", taskNumber: 42, worktreeLocation: "~/.devdesk/wt")
        sessions.markEnded(taskID: "42", status: 0)
        XCTAssertEqual(sessions.state(for: "42"), .failed(Self.noFolder))
        XCTAssertEqual(sessions.runningTaskIDs, [])
        XCTAssertEqual(runner.calls, [])
    }

    func testTheWindowModelGivesALocalProjectItsFolderAndASampleNone() async {
        let local = ProjectWindowModel(ref: .local(path: "/work/My App"), source: FailingSource(message: "not loaded"))
        await local.shellSessions.refreshPlan(taskID: "14", branch: nil, taskNumber: nil, worktreeLocation: "~/.devdesk/wt")
        XCTAssertEqual(local.shellSessions.state(for: "14"), .idle(.root(Self.root, note: "No branch for this task yet. The shell opens at the project root.")))
        let sample = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))
        XCTAssertEqual(sample.shellSessions.state(for: "42"), .failed(Self.noFolder))
    }
}
