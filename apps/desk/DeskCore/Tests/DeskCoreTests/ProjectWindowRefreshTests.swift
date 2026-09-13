import XCTest
@testable import DeskCore

/// Counts its loads and records what `probe` returned during each, so a test can see the model mid-load.
private final class ProbeSource: ProjectDataSource {
    private let lock = NSLock()
    private var count = 0
    private var observed: [Bool] = []
    var probe: (() async -> Bool)?

    var loads: Int { lock.withLock { count } }
    var seen: [Bool] { lock.withLock { observed } }

    func load() async throws -> ProjectSnapshot {
        lock.withLock { count += 1 }
        if let probe {
            let value = await probe()
            lock.withLock { observed.append(value) }
        }
        return try await SampleDataSource(project: .studyHub).load()
    }
}

@MainActor
final class ProjectWindowRefreshTests: XCTestCase {
    func testALoadRecordsWhenItFinished() async throws {
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub), insightsDelay: .zero)
        XCTAssertNil(model.lastLoadedAt)
        let before = Date()
        await model.load()
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(model.lastLoadedAt), before)
    }

    func testTheModelSaysItIsRefreshingOnlyWhileALoadRuns() async {
        let source = ProbeSource()
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: source, insightsDelay: .zero)
        source.probe = { await MainActor.run { model.isRefreshing } }
        await model.load()
        XCTAssertEqual(source.seen, [true])
        XCTAssertFalse(model.isRefreshing)
    }

    func testALocalProjectReloadsOnItsIntervalUntilCancelled() async throws {
        let source = ProbeSource()
        let model = ProjectWindowModel(ref: .local(path: "/tmp/devdesk-refresh-test"), source: source, insightsDelay: .zero)
        let loop = Task { await model.refresh(every: .milliseconds(10)) }
        let deadline = Date().addingTimeInterval(5)
        while source.loads < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        loop.cancel()
        XCTAssertGreaterThanOrEqual(source.loads, 3)
        let settled = source.loads
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertLessThanOrEqual(source.loads, settled + 1, "cancelling the task stops the timer")
    }

    func testASampleProjectNeverReloadsOnATimer() async throws {
        let source = ProbeSource()
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: source, insightsDelay: .zero)
        let loop = Task { await model.refresh(every: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(60))
        loop.cancel()
        XCTAssertEqual(source.loads, 0)
    }

    func testTheUpdatedLabelCountsSecondsThenWholeMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ProjectWindowModel.updatedLabel(since: now.addingTimeInterval(-2), now: now), "Updated just now")
        XCTAssertEqual(ProjectWindowModel.updatedLabel(since: now.addingTimeInterval(-40), now: now), "Updated 40 s ago")
        XCTAssertEqual(ProjectWindowModel.updatedLabel(since: now.addingTimeInterval(-150), now: now), "Updated 2 min ago")
        XCTAssertEqual(ProjectWindowModel.updatedLabel(since: now.addingTimeInterval(5), now: now), "Updated just now", "a clock step backwards")
    }
}

/// The board's own liveness. It asked only about door runs until a started shell and a started agent both
/// proved invisible on it; since ADR 0026 a task has ONE session, so what is left to decide is which kind.
@MainActor
final class TaskActivityTests: XCTestCase {
    private let folder = TaskFolder(url: URL(fileURLWithPath: "/tmp/x"), note: nil, created: false)

    func testNothingLiveIsNoActivity() {
        XCTAssertNil(ProjectWindowModel.activity(doorRun: false, session: .idle(nil), purpose: nil))
    }

    func testASessionNamesItsOwnKind() {
        XCTAssertEqual(ProjectWindowModel.activity(doorRun: false, session: .running(folder), purpose: .shell), .shell)
        XCTAssertEqual(ProjectWindowModel.activity(doorRun: false, session: .running(folder), purpose: .agent), .agent)
    }

    /// A session that started before anything recorded a purpose is a shell: it is what `start` defaults to.
    func testASessionWithNoRecordedPurposeIsAShell() {
        XCTAssertEqual(ProjectWindowModel.activity(doorRun: false, session: .running(folder), purpose: nil), .shell)
    }

    func testPreparingCountsBeforeAnythingRuns() {
        XCTAssertEqual(ProjectWindowModel.activity(doorRun: false, session: .preparing, purpose: .agent), .agent)
    }

    func testADoorRunSpeaksForTheWholeTask() {
        XCTAssertEqual(ProjectWindowModel.activity(doorRun: true, session: .running(folder), purpose: .agent), .run)
    }

    func testAFinishedSessionIsNotLive() {
        XCTAssertNil(ProjectWindowModel.activity(doorRun: false, session: .ended(folder, status: 0), purpose: .agent))
        XCTAssertNil(ProjectWindowModel.activity(doorRun: false, session: .failed("no"), purpose: .shell))
    }

    func testEachKindNamesItselfOnTheCard() {
        XCTAssertEqual(TaskActivity.run.label, "Running")
        XCTAssertEqual(TaskActivity.shell.label, "Shell")
        XCTAssertEqual(TaskActivity.agent.label, "Agent")
    }
}
