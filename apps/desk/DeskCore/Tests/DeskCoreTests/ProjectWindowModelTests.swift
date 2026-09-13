import XCTest
@testable import DeskCore

@MainActor
final class ProjectWindowModelTests: XCTestCase {
    private func makeStudyHubModel() async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub), insightsDelay: .zero)
        await model.load()
        return model
    }

    func testLoadAppliesStudyHubLaunchState() async {
        let model = await makeStudyHubModel()
        XCTAssertEqual(model.selectedTaskID, "42")
        XCTAssertEqual(model.tab, .activity)
        XCTAssertEqual(model.destination, .board)
        XCTAssertEqual(model.selectedFindingID, "F-108")
        XCTAssertEqual(model.selectedRunID, "run-0940")
    }

    func testIgnoringAFindingDropsTheSelectionAndIsRestorable() async {
        let model = await makeStudyHubModel()
        defer { UserDefaults.standard.removeObject(forKey: ProjectWindowModel.ignoredKey(model.ref)) }
        model.selectedFindingID = "F-108"

        model.ignoreFinding("F-108")
        XCTAssertTrue(model.ignoredFindings.contains("F-108"))
        // The detail pane was showing it; leaving it selected would keep an ignored finding on screen.
        XCTAssertNil(model.selectedFindingID)

        model.restoreFinding("F-108")
        XCTAssertFalse(model.ignoredFindings.contains("F-108"))
    }

    func testIgnoredFindingsAreKeptPerProject() async {
        let model = await makeStudyHubModel()
        let other = ProjectWindowModel(ref: .local(path: "/tmp/other-project"), source: SampleDataSource(project: .studyHub),
                                       insightsDelay: .zero)
        defer {
            UserDefaults.standard.removeObject(forKey: ProjectWindowModel.ignoredKey(model.ref))
            UserDefaults.standard.removeObject(forKey: ProjectWindowModel.ignoredKey(other.ref))
        }

        model.ignoreFinding("F-108")
        XCTAssertTrue(model.ignoredFindings.contains("F-108"))
        XCTAssertFalse(other.ignoredFindings.contains("F-108"))
    }

    func testGoBoardClearsSelectionButKeepsLastOpened() async {
        let model = await makeStudyHubModel()
        model.openTask("57")
        model.go(.board)
        XCTAssertNil(model.selectedTaskID)
        XCTAssertEqual(model.lastOpenedTaskID, "57")
        XCTAssertEqual(model.mode, .focus)
    }

    func testAWaitingDecisionOpensTheTaskItBelongsTo() async {
        let model = await makeStudyHubModel()
        model.openTask("57")
        let url = model.performNextAction()
        XCTAssertNil(url)
        XCTAssertEqual(model.sheet, .task("57"), "the question lives on the task, not in a destination")
    }

    func testNextActionOf63OpensHandoff() async {
        let model = await makeStudyHubModel()
        model.openTask("63")
        _ = model.performNextAction()
        XCTAssertEqual(model.sheet, .handoff)
    }

    func testNextActionOf42ShowsChanges() async {
        let model = await makeStudyHubModel()
        model.openTask("42")
        _ = model.performNextAction()
        XCTAssertEqual(model.tab, .changes)
    }

    func testParallelModeReturnsToBoard() async {
        let model = await makeStudyHubModel()
        model.go(.survey)
        model.setMode(.parallel)
        XCTAssertEqual(model.destination, .board)
        XCTAssertEqual(model.parallelTasks.map(\.id), ["42", "57"])
    }

    func testConfirmHandoffRecordsDemoEvent() async {
        let model = await makeStudyHubModel()
        model.openTask("63")
        model.present(.handoff)
        model.confirmSheet(provider: "Claude")
        XCTAssertNil(model.sheet)
        let firstEvent = model.task("63")?.activity.value?.first
        XCTAssertTrue(firstEvent?.text.hasPrefix("New Claude session") ?? false)
    }

    func testReconcileQueuesUpdateLocally() async {
        let model = await makeStudyHubModel()
        model.present(.reconcileFinding("F-108"))
        model.confirmSheet()
        let finding = model.snapshot?.findings.value?.findings.first { $0.id == "F-108" }
        XCTAssertNotNil(finding?.reconcile?.queuedNote)
    }

    func testDemoMutationsIgnoredForRealSnapshots() async {
        let snapshot = ProjectSnapshot(
            project: ProjectInfo(name: "Real", displayPath: "~/real", branch: "main"),
            isDemo: false, board: .available([]), boardNote: "",
            findings: .available(FindingsReport(runs: [], findings: [])), roadmap: .unavailable("n/a"),
            connections: [], connectionsNote: "",
            capabilities: CapabilityMatrix(providers: [], rows: [], note: ""), insights: .unavailable("n/a"))
        let model = ProjectWindowModel(ref: .local(path: "/tmp/real-project"), source: FixedSource(snapshot: snapshot), insightsDelay: .zero)
        await model.load()
        model.present(.reconcileFinding("F-1"))
        model.confirmSheet()
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.snapshot?.findings.value?.findings.isEmpty, true, "a real snapshot is never mutated by a demo action")
    }

    func testConcurrentLoadsReadTheSourceOnce() async {
        let source = CountingSource(snapshot: SampleData.studyHub())
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: source, insightsDelay: .zero)
        async let first: Void = model.load()
        async let second: Void = model.load()
        _ = await (first, second)
        let loads = await source.counter.value
        XCTAssertEqual(loads, 1)
        XCTAssertNotNil(model.snapshot)
    }

    func testCancelledLoadLeavesStateAsItWasAndAllowsTheNextLoad() async {
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SleepThenReturnSource(snapshot: SampleData.studyHub()), insightsDelay: .zero)
        let loading = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(20))
        loading.cancel()
        await loading.value
        guard case .loading = model.loadState else {
            XCTFail("a cancelled load must leave the state as it was")
            return
        }
        XCTAssertNil(model.selectedTaskID)
        XCTAssertNil(model.reloadError)
        await model.load()
        XCTAssertNotNil(model.snapshot)
    }

    func testSequentialLoadsEachReadTheSource() async {
        let source = CountingSource(snapshot: SampleData.studyHub())
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: source, insightsDelay: .zero)
        await model.load()
        await model.load()
        let loads = await source.counter.value
        XCTAssertEqual(loads, 2)
    }

    private func trackerSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            project: ProjectInfo(name: "Real", displayPath: "~/real", branch: "main"),
            isDemo: false, board: .available([]), boardNote: "",
            findings: .unavailable("n/a"), roadmap: .unavailable("n/a"),
            connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
            insights: .unavailable("n/a"), slug: "owner/repo", activeMilestone: "1.4")
    }

    func testQueueingACardWritesToTheTrackerAndReloads() async {
        let runner = FakeRunner(["gh issue edit 7 --repo owner/repo --milestone 1.4": .ok()])
        let model = ProjectWindowModel(ref: .local(path: "/tmp/real"), source: FixedSource(snapshot: trackerSnapshot()),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        await model.performTrackerWrite(issue: 7, action: .queue(milestone: "1.4"))
        XCTAssertEqual(runner.keys, ["gh issue edit 7 --repo owner/repo --milestone 1.4"])
        XCTAssertNil(model.writeFailure)
        XCTAssertEqual(model.activeMilestone, "1.4")
    }

    func testAFailedTrackerWriteIsReported() async {
        let runner = FakeRunner(["gh issue edit 7 --repo owner/repo --remove-milestone": .failed(1, stderr: "HTTP 403\n")])
        let model = ProjectWindowModel(ref: .local(path: "/tmp/real"), source: FixedSource(snapshot: trackerSnapshot()),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        await model.performTrackerWrite(issue: 7, action: .backlog)
        XCTAssertEqual(model.writeFailure?.message.contains("HTTP 403"), true)
        XCTAssertEqual(model.writeFailure?.title, "The tracker was not changed")
        model.dismissWriteFailure()
        XCTAssertNil(model.writeFailure)
    }

    func testASampleProjectWritesNothingToTheTracker() async {
        let runner = FakeRunner()
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        await model.performTrackerWrite(issue: 42, action: .backlog)
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertNotNil(model.writeFailure)
    }

    func testEveryCardOpensTheSameDialog() async {
        let model = await makeStudyHubModel()
        model.openTask("65")
        XCTAssertEqual(model.sheet, .task("65"))
        XCTAssertEqual(model.tab, .requirements, "an unstarted task opens on its description")
        model.openTask("57")
        XCTAssertEqual(model.sheet, .task("57"))
        XCTAssertEqual(model.tab, .activity, "work already under way opens on what happened")
        XCTAssertEqual(model.destination, .board, "selecting a card never navigates away from the board")
    }

    func testShowingRunsOpensThePanel() async {
        let model = await makeStudyHubModel()
        model.showRuns()
        XCTAssertTrue(model.runsOpen)
        model.showRuns()
        XCTAssertTrue(model.runsOpen, "asking for the panel twice never closes it")
        model.toggleRuns()
        XCTAssertFalse(model.runsOpen)
    }

    func testRunsAndFilesOpenIndependently() async {
        let model = await makeStudyHubModel()
        model.showRuns()
        model.showFiles()
        XCTAssertTrue(model.runsOpen)
        XCTAssertTrue(model.filesOpen)
        model.toggleRuns()
        XCTAssertFalse(model.runsOpen)
        XCTAssertTrue(model.filesOpen, "closing one panel never closes the other")
    }

    func testLinkRoutesToFinding() async {
        let model = await makeStudyHubModel()
        model.handle(.finding("F-093"))
        XCTAssertEqual(model.destination, .survey)
        XCTAssertEqual(model.selectedFindingID, "F-093")
    }

    func testFailedFirstLoadReportsMessage() async {
        let model = ProjectWindowModel(ref: .local(path: "/nope"), source: FailingSource(message: "boom"), insightsDelay: .zero)
        await model.load()
        guard case .failed(let message) = model.loadState else {
            XCTFail("expected a failed load state")
            return
        }
        XCTAssertTrue(message.contains("boom"))
    }
}

private actor LoadCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Like a local read that turns cancellation into a result instead of throwing.
private struct SleepThenReturnSource: ProjectDataSource {
    let snapshot: ProjectSnapshot

    func load() async throws -> ProjectSnapshot {
        try? await Task.sleep(for: .milliseconds(300))
        return snapshot
    }
}

private struct CountingSource: ProjectDataSource {
    let snapshot: ProjectSnapshot
    let counter = LoadCounter()

    func load() async throws -> ProjectSnapshot {
        await counter.increment()
        try await Task.sleep(for: .milliseconds(50))
        return snapshot
    }
}
