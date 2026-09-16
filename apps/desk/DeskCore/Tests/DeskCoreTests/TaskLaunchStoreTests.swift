import XCTest
@testable import DeskCore

@MainActor
final class TaskLaunchStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("launch-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func launch(agent: AgentKind, mode: RunMode) -> TaskLaunch {
        TaskLaunch(id: DoorRuns.id(task: 212), task: "212", title: "Resume upload cap", door: "dev",
                   arguments: ["#212"], agent: agent, mode: mode, worktreeLocation: "~/.devdesk/wt",
                   base: LaunchBase(ref: "origin/main", short: "8c1f2a0"))
    }

    /// The defect this store exists for: a card parked under one agent must not start under another because
    /// the preferences moved while it sat in the queue.
    func testAParkedLaunchIsReadBackExactlyHoweverThePreferencesMove() {
        let store = TaskLaunchStore(projectRoot: root)
        store.write(launch(agent: .codex, mode: .delegate))

        let released = store.read(id: DoorRuns.id(task: 212))
        XCTAssertEqual(released?.agent, .codex)
        XCTAssertEqual(released?.mode, .delegate)
        XCTAssertEqual(released?.base?.display, "origin/main@8c1f2a0")
        XCTAssertEqual(released, launch(agent: .codex, mode: .delegate))
    }

    /// nil is the safe reading: the caller rebuilds from today's values, which is what happened before.
    func testAnAbsentLaunchReadsAsNilRatherThanThrowing() {
        XCTAssertNil(TaskLaunchStore(projectRoot: root).read(id: DoorRuns.id(task: 999)))
    }

    func testADispatchedLaunchIsCleared() {
        let store = TaskLaunchStore(projectRoot: root)
        store.write(launch(agent: .claude, mode: .standard))
        store.clear(id: DoorRuns.id(task: 212))
        XCTAssertNil(store.read(id: DoorRuns.id(task: 212)))
    }

    func testTheFileLandsUnderDevdeskLaunchWithAnIdThatIsSafeInAPath() {
        let store = TaskLaunchStore(projectRoot: root)
        let url = store.url(for: DoorRuns.id(task: 212))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "launch")
        XCTAssertFalse(url.lastPathComponent.contains(":"), "a colon in an id must not reach the filename")
        XCTAssertEqual(url.lastPathComponent, "task-212.json")
    }

    /// A project with no folder has nowhere to keep a launch, and must not crash trying.
    func testWritingWhereThereIsNoFolderIsSilentRatherThanFatal() {
        let store = TaskLaunchStore(projectRoot: URL(fileURLWithPath: "/dev/null/nope"))
        store.write(launch(agent: .claude, mode: .standard))
        XCTAssertNil(store.read(id: DoorRuns.id(task: 212)))
    }

    private func task(_ id: String, issue: Int? = nil) -> DeskTask {
        DeskTask(id: id, issueNumber: issue, title: id, column: .readyForDev,
                 headerBadge: StatusBadge(.neutral, id), branchLine: "", requirements: .unavailable(""),
                 changes: .unavailable(""), evidence: .unavailable(""), parallel: .none(""))
    }

    /// One rule for which run a card is, so the Start, the queue and the parked launch cannot disagree.
    func testTheRunIdComesFromTheIssueNumberOrTheLocalEntry() {
        XCTAssertEqual(DoorRuns.id(for: task("212", issue: 212)), "task:212")
        XCTAssertEqual(DoorRuns.id(for: task("local:abc")), "local:abc")
        XCTAssertNil(DoorRuns.id(for: task("branch:x")), "a card /dev has nothing to open has no run id")
    }
}
