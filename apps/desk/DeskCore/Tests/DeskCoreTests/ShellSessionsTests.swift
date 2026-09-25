import Foundation
import XCTest
@testable import DeskCore

/// Holds the first call it gets until `release()` and lets every later one through, so a test can act while a start or a refresh
/// waits on git, and a call that should never have happened finishes, and shows, instead of hanging the test.
final class HeldRunner: CommandRunner {
    private let inner: CommandRunner
    private let lock = NSLock()
    private var isReleased = false
    private var hasHeld = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ inner: CommandRunner) { self.inner = inner }

    /// True while the first call waits.
    var isHolding: Bool { lock.withLock { held != nil } }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isReleased = true
            defer { held = nil }
            return held
        }
        waiting?.resume()
    }

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        await withCheckedContinuation { continuation in
            let proceed = lock.withLock { () -> Bool in
                if isReleased || hasHeld { return true }
                hasHeld = true
                held = continuation
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
    /// A new worktree is followed by the read that finds the untracked env files to copy into it.
    private static let envKey = FakeRunner.gitRead("ls-files -z --others --ignored --exclude-standard --directory")
    private static let mainOnly = "worktree /work/My App\0HEAD \(String(repeating: "1", count: 40))\0branch refs/heads/main\0\0"
    private static let noFolder = "Sample projects have no folder, so there is no shell to start."

    private func addKey(_ path: URL) -> String { FakeRunner.gitRead("worktree add \(path.path) gh-7-demo") }

    /// git's list once the folder at `path` holds gh-7-demo, so a later start opens in it.
    private func listing(_ path: URL) -> String {
        Self.mainOnly + "worktree \(path.path)\0HEAD \(String(repeating: "2", count: 40))\0branch refs/heads/gh-7-demo\0\0"
    }

    func testAnUnseenTaskIsIdleWithoutAPlanAndRunsNothing() {
        let runner = FakeRunner()
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        XCTAssertEqual(sessions.state(for: "7"), .idle(nil))
        XCTAssertEqual(sessions.generation(for: "7"), 0)
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
        let fork = "This pull request comes from a fork, so its branch isn't in this repository. The shell opens at the project root."
        await sessions.refreshPlan(taskID: "pr:60", branch: nil, taskNumber: nil, noBranchNote: fork, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "pr:60"), .idle(.root(Self.root, note: fork)))
        XCTAssertEqual(runner.keys, [Self.listKey, Self.listKey],
                       "a task with a branch or a number reads the worktree list (rules 1 and 1b); one with neither reads nothing")
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

    func testARefreshThatFinishesAfterAStartLeavesTheSessionRunning() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let runner = HeldRunner(fake)
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        let refresh = Task { await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path) }
        await waitUntil { runner.isHolding }

        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        let running = ShellSessionState.running(TaskFolder(url: path, note: nil, created: true))
        XCTAssertEqual(sessions.state(for: "7"), running)

        runner.release()
        await refresh.value
        XCTAssertEqual(sessions.state(for: "7"), running, "the refresh read its plan before the start; storing it would hide the running shell")
    }

    func testStartGoesFromIdleThroughPreparingToRunningAndIgnoresADoubleClick() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let runner = HeldRunner(fake)
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        XCTAssertEqual(sessions.state(for: "7"), .idle(nil))

        let start = Task { await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path) }
        await waitUntil { runner.isHolding }
        XCTAssertEqual(sessions.state(for: "7"), .preparing)
        XCTAssertEqual(sessions.runningTaskIDs, [])

        // A second click while the first start waits on git. The runner lets later calls through, so a start that got past
        // the guard would plan and create a second time.
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .preparing)

        runner.release()
        await start.value
        XCTAssertEqual(sessions.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: true)))
        XCTAssertEqual(sessions.runningTaskIDs, ["7"])
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path), Self.envKey], "one worktree list, one worktree add, one env-file read")
    }

    func testStartPlansWithTheLocationGivenAtTheClickNotAnEarlierRefresh() async throws {
        let before = try TempGitRepo()
        let now = try TempGitRepo()
        let stale = before.url.appendingPathComponent("my-app-7", isDirectory: true)
        let path = now.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let sessions = ShellSessions(projectRoot: Self.root, runner: fake)
        await sessions.refreshPlan(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: before.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .idle(.create(path: stale, branch: "gh-7-demo")))

        // The worktree location changed in Settings between the preview and the click.
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: now.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: true)))
        XCTAssertEqual(fake.keys, [Self.listKey, Self.listKey, addKey(path), Self.envKey])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
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
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path), Self.envKey])

        sessions.markEnded(taskID: "7", status: 129, generation: sessions.generation(for: "7"))
        sessions.markEnded(taskID: "8", status: 0, generation: sessions.generation(for: "8"))
        XCTAssertEqual(sessions.state(for: "7"), .ended(created, status: 129))
        XCTAssertEqual(sessions.state(for: "8"), .idle(nil), "only a running session can end")
        XCTAssertEqual(sessions.runningTaskIDs, [])

        // git now lists the folder the first start made, so starting again opens in it instead of making another.
        fake.script(Self.listKey, .ok(listing(path)))
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: false)))
        XCTAssertEqual(fake.keys, [Self.listKey, addKey(path), Self.envKey, Self.listKey])
    }

    func testALateExitFromAnEarlierRunLeavesTheNewRunRunning() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), addKey(path): .ok()])
        let sessions = ShellSessions(projectRoot: Self.root, runner: fake)
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        let first = sessions.generation(for: "7")
        XCTAssertEqual(first, 1)
        // End shell: the app marks the session ended at once, before the process has gone.
        sessions.markEnded(taskID: "7", status: nil, generation: first)
        XCTAssertEqual(sessions.state(for: "7"), .ended(TaskFolder(url: path, note: nil, created: true), status: nil))

        fake.script(Self.listKey, .ok(listing(path)))
        await sessions.start(taskID: "7", branch: "gh-7-demo", taskNumber: 7, worktreeLocation: location.url.path)
        let second = sessions.generation(for: "7")
        XCTAssertEqual(second, 2)
        let rerun = ShellSessionState.running(TaskFolder(url: path, note: nil, created: false))
        XCTAssertEqual(sessions.state(for: "7"), rerun)

        // The first shell's exit, after its SIGHUP, arrives only now.
        sessions.markEnded(taskID: "7", status: 129, generation: first)
        XCTAssertEqual(sessions.state(for: "7"), rerun)
        XCTAssertEqual(sessions.runningTaskIDs, ["7"])

        sessions.markEnded(taskID: "7", status: 0, generation: second)
        XCTAssertEqual(sessions.state(for: "7"), .ended(TaskFolder(url: path, note: nil, created: false), status: 0))
    }

    func testASampleSessionFailsWithItsReasonAndNeverRunsACommand() async {
        let runner = FakeRunner()
        let sessions = ShellSessions(projectRoot: nil, runner: runner)
        await sessions.refreshPlan(taskID: "42", branch: "fix/42-course-scroll", taskNumber: 42, worktreeLocation: "~/.devdesk/wt")
        await sessions.start(taskID: "42", branch: "fix/42-course-scroll", taskNumber: 42, worktreeLocation: "~/.devdesk/wt")
        sessions.markEnded(taskID: "42", status: 0, generation: 0)
        XCTAssertEqual(sessions.state(for: "42"), .failed(Self.noFolder))
        XCTAssertEqual(sessions.generation(for: "42"), 0)
        XCTAssertEqual(sessions.runningTaskIDs, [])
        XCTAssertEqual(runner.calls, [])
    }

    /// One registry per window since ADR 0026: the same session plans as a shell or as an agent depending on
    /// what is starting, and the refusal a sample gives names whichever was asked for.
    func testTheWindowModelGivesALocalProjectItsFolderAndASampleNone() async {
        let local = ProjectWindowModel(ref: .local(path: "/work/My App"), source: FailingSource(message: "not loaded"))
        let unbranched = ShellSessionState.idle(.root(Self.root, note: "No branch for this task yet. The shell opens at the project root."))
        await local.sessions.refreshPlan(taskID: "14", branch: nil, taskNumber: nil, worktreeLocation: "~/.devdesk/wt")
        XCTAssertEqual(local.sessions.state(for: "14"), unbranched)

        let agentPlan = ProjectWindowModel(ref: .local(path: "/work/My App"), source: FailingSource(message: "not loaded"))
        await agentPlan.sessions.refreshPlan(taskID: "14", purpose: .agent, branch: nil, taskNumber: nil,
                                             worktreeLocation: "~/.devdesk/wt", baseRef: Self.base)
        XCTAssertEqual(agentPlan.sessions.state(for: "14"),
                       .idle(.root(Self.root, note: "No branch for this task yet. The agent opens at the project root.")),
                       "planning as an agent speaks of the agent, in the same project and the same registry")

        let sample = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))
        XCTAssertEqual(sample.sessions.state(for: "42"), .failed(Self.noFolder))
        XCTAssertEqual(sample.sessions.startRefusal(for: .agent), Self.noFolderForAgent)
        XCTAssertEqual(sample.sessions.startRefusal(for: .shell), Self.noFolder)
    }

    // MARK: - Agent sessions

    private static let base = "refs/remotes/origin/main"
    private static let noFolderForAgent = "Sample projects have no folder, so there is no agent to start."

    private func detachKey(_ path: URL) -> String { FakeRunner.gitRead("worktree add --detach \(path.path) \(Self.base)") }

    func testAnAgentSessionPlansADetachedWorktreeWhereAShellPlansTheRoot() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly)])
        let agents = ShellSessions(projectRoot: Self.root, runner: runner)
        let shells = ShellSessions(projectRoot: Self.root, runner: runner)
        await agents.refreshPlan(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base)
        await shells.refreshPlan(taskID: "7", branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base)
        XCTAssertEqual(agents.state(for: "7"), .idle(.createDetached(path: location.url.appendingPathComponent("my-app-7", isDirectory: true), baseRef: Self.base)))
        XCTAssertEqual(shells.state(for: "7"), .idle(.root(Self.root, note: "No branch for #7 yet. The shell opens at the project root; "
                                                          + "running /dev #7 there cuts gh-7-… at its first write.")),
                       "a shell never makes a detached worktree")
        await agents.refreshPlan(taskID: "8", purpose: .agent, branch: nil, taskNumber: 8, worktreeLocation: location.url.path)
        XCTAssertEqual(agents.state(for: "8"), .idle(.root(Self.root, note: "No base branch is known, so the agent opens at the project root.")))
    }

    func testStartingAnAgentCreatesItsDetachedWorktreeAndAnotherStartReusesIt() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), detachKey(path): .ok()])
        let agents = ShellSessions(projectRoot: Self.root, runner: fake)
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base)
        let created = TaskFolder(url: path, note: nil, created: true)
        XCTAssertEqual(agents.state(for: "7"), .running(created))
        XCTAssertEqual(agents.runningTaskIDs, ["7"])
        XCTAssertEqual(fake.keys, [Self.listKey, detachKey(path), Self.envKey])

        agents.markEnded(taskID: "7", status: 0, generation: agents.generation(for: "7"))
        XCTAssertEqual(agents.state(for: "7"), .ended(created, status: 0))

        // git now lists the detached worktree at the task's own path, so starting again opens in it (rule 1b).
        fake.script(Self.listKey, .ok(Self.mainOnly + "worktree \(path.path)\0HEAD \(String(repeating: "2", count: 40))\0detached\0\0"))
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base)
        XCTAssertEqual(agents.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: false)))
        XCTAssertEqual(fake.keys, [Self.listKey, detachKey(path), Self.envKey, Self.listKey])
    }

    func testASampleAgentSessionFailsWithItsReasonAndNeverRunsACommand() async {
        let runner = FakeRunner()
        let agents = ShellSessions(projectRoot: nil, runner: runner)
        await agents.refreshPlan(taskID: "42", purpose: .agent, branch: nil, taskNumber: 42, worktreeLocation: "~/.devdesk/wt", baseRef: Self.base)
        await agents.start(taskID: "42", purpose: .agent, branch: nil, taskNumber: 42, worktreeLocation: "~/.devdesk/wt", baseRef: Self.base)
        XCTAssertEqual(agents.startRefusal(for: .agent), Self.noFolderForAgent)
        XCTAssertEqual(agents.runningTaskIDs, [])
        XCTAssertEqual(runner.calls, [])
    }

    // MARK: - Auto: a start that refuses the project root, and the slots starts hold

    private static let noBase = "No base branch is known, so the agent opens at the project root."

    func testAStartThatRefusesTheRootFailsWithThePlansNoteAndLaunchesNothing() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly)])
        let agents = ShellSessions(projectRoot: Self.root, runner: runner)
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, refusingRoot: true)
        XCTAssertEqual(agents.state(for: "7"), .failed(Self.noBase))
        XCTAssertEqual(agents.generation(for: "7"), 0, "nothing moved to running, so there is no process to launch")
        XCTAssertEqual(agents.runningTaskIDs, [])
        XCTAssertEqual(agents.activeTaskIDs, [])
        XCTAssertEqual(runner.keys, [Self.listKey], "and no worktree add")

        // Started by hand, without the refusal, the same task opens at the project root as before.
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path)
        XCTAssertEqual(agents.state(for: "7"), .running(TaskFolder(url: Self.root, note: Self.noBase, created: false)))
    }

    func testAStartThatRefusesTheRootFailsWhenGitRefusesTheWorktree() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly), detachKey(path): .failed(128, stderr: "fatal: invalid reference: \(Self.base)\n")])
        let agents = ShellSessions(projectRoot: Self.root, runner: runner)
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base, refusingRoot: true)
        XCTAssertEqual(agents.state(for: "7"), .failed("Couldn't create a worktree for \(Self.base), so the agent opens at the project root: "
                                                      + "fatal: invalid reference: \(Self.base)"))
        XCTAssertEqual(agents.generation(for: "7"), 0)
        XCTAssertEqual(agents.activeTaskIDs, [])
        XCTAssertEqual(runner.keys, [Self.listKey, detachKey(path)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "the folder it claimed is given back")
    }

    func testAStartThatRefusesTheRootStillRunsInTheTasksOwnWorktree() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly), detachKey(path): .ok()])
        let agents = ShellSessions(projectRoot: Self.root, runner: runner)
        await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base, refusingRoot: true)
        XCTAssertEqual(agents.state(for: "7"), .running(TaskFolder(url: path, note: nil, created: true)))
        XCTAssertEqual(agents.generation(for: "7"), 1)
    }

    func testActiveTaskIDsHoldAStartStillPreparingWhereRunningTaskIDsDoNot() async throws {
        let location = try TempGitRepo()
        let path = location.url.appendingPathComponent("my-app-7", isDirectory: true)
        let fake = FakeRunner([Self.listKey: .ok(Self.mainOnly), detachKey(path): .ok()])
        let runner = HeldRunner(fake)
        let agents = ShellSessions(projectRoot: Self.root, runner: runner)
        XCTAssertEqual(agents.activeTaskIDs, [])

        let start = Task { await agents.start(taskID: "7", purpose: .agent, branch: nil, taskNumber: 7, worktreeLocation: location.url.path, baseRef: Self.base) }
        await waitUntil { runner.isHolding }
        XCTAssertEqual(agents.state(for: "7"), .preparing)
        XCTAssertEqual(agents.activeTaskIDs, ["7"], "a start waiting on git already holds its slot")
        XCTAssertEqual(agents.runningTaskIDs, [])

        runner.release()
        await start.value
        XCTAssertEqual(agents.activeTaskIDs, ["7"])
        XCTAssertEqual(agents.runningTaskIDs, ["7"])

        agents.markEnded(taskID: "7", status: 0, generation: agents.generation(for: "7"))
        XCTAssertEqual(agents.activeTaskIDs, [])
        XCTAssertEqual(agents.runningTaskIDs, [])
    }

    func testOnlySessionsStartedToRunAnAgentHoldAnAgentSlot() async throws {
        let location = try TempGitRepo()
        let runner = FakeRunner([Self.listKey: .ok(Self.mainOnly)])
        let sessions = ShellSessions(projectRoot: Self.root, runner: runner)
        await sessions.start(taskID: "door:dev", branch: nil, taskNumber: nil, worktreeLocation: location.url.path, executable: "claude")
        await sessions.start(taskID: "scratch", branch: nil, taskNumber: nil, worktreeLocation: location.url.path)
        await sessions.start(taskID: "doctor", branch: nil, taskNumber: nil, worktreeLocation: location.url.path, executable: "dev")
        XCTAssertEqual(sessions.activeTaskIDs, ["doctor", "door:dev", "scratch"])
        XCTAssertEqual(sessions.activeAgentTaskIDs, ["door:dev"], "a plain shell, even one someone typed claude into, is not a slot")

        // A shell reopened on an ended agent's id is a shell again.
        sessions.markEnded(taskID: "door:dev", status: 0, generation: sessions.generation(for: "door:dev"))
        await sessions.start(taskID: "door:dev", branch: nil, taskNumber: nil, worktreeLocation: location.url.path)
        XCTAssertEqual(sessions.activeAgentTaskIDs, [])
    }
}
