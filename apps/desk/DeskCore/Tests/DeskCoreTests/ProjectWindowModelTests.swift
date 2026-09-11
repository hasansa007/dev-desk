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
        XCTAssertTrue(model.insightsOpen)
        XCTAssertEqual(model.destination, .board)
        XCTAssertEqual(model.selectedDecisionID, "d-57")
        XCTAssertEqual(model.selectedFindingID, "F-108")
        XCTAssertEqual(model.selectedRunID, "run-0940")
    }

    func testGoBoardClearsSelectionButKeepsLastOpened() async {
        let model = await makeStudyHubModel()
        model.openTask("57")
        model.go(.board)
        XCTAssertNil(model.selectedTaskID)
        XCTAssertEqual(model.lastOpenedTaskID, "57")
        XCTAssertEqual(model.mode, .focus)
    }

    func testNextActionOf57OpensItsDecision() async {
        let model = await makeStudyHubModel()
        model.openTask("57")
        let url = model.performNextAction()
        XCTAssertNil(url)
        XCTAssertEqual(model.destination, .decisions)
        XCTAssertEqual(model.decisionsTab, .needsAttention)
        XCTAssertEqual(model.selectedDecisionID, "d-57")
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
        model.go(.findings)
        model.setMode(.parallel)
        XCTAssertEqual(model.destination, .board)
        XCTAssertEqual(model.parallelTasks.map(\.id), ["42", "57"])
    }

    func testSideDockPlacementOpensDock() async {
        let model = await makeStudyHubModel()
        model.dockOpen = false
        model.setDockPlacement(.side)
        XCTAssertEqual(model.dockPlacement, .side)
        XCTAssertTrue(model.dockOpen)
    }

    func testViewActivityOpensSplitDock() async {
        let model = await makeStudyHubModel()
        model.openTask("42")
        model.dockOpen = false
        model.dockSplit = false
        model.perform(.viewActivity, agentID: "reviewer")
        XCTAssertTrue(model.dockOpen)
        XCTAssertTrue(model.dockSplit)
    }

    func testRecordAnswerResumesTask57() async {
        let model = await makeStudyHubModel()
        model.recordAnswer(decisionID: "d-57", optionID: "checkpoint", rationale: "Balanced")
        XCTAssertEqual(model.pendingDecisionCount, 0)
        let task57 = try? XCTUnwrap(model.task("57"))
        XCTAssertEqual(task57?.headerBadge.tone, .running)
        XCTAssertNil(task57?.nextAction)
        let decision = model.snapshot?.decisions.value?.first { $0.id == "d-57" }
        XCTAssertEqual(decision?.answer?.optionTitle, "Checkpoint every N answers and on blur")
        XCTAssertEqual(model.answeredDecisionID, "d-57")
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
        let decision = Decision(id: "d-1", listTitle: "x", listMeta: "y", state: .needsAttention, question: "q", context: "c")
        let snapshot = ProjectSnapshot(
            project: ProjectInfo(name: "Real", displayPath: "~/real", branch: "main"),
            isDemo: false, board: .available([]), boardNote: "",
            findings: .unavailable("n/a"), roadmap: .unavailable("n/a"), decisions: .available([decision]),
            connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
            insights: .unavailable("n/a")
        )
        let model = ProjectWindowModel(ref: .local(path: "/tmp/real-project"), source: FixedSource(snapshot: snapshot), insightsDelay: .zero)
        await model.load()
        model.recordAnswer(decisionID: "d-1", optionID: nil, rationale: "test")
        XCTAssertEqual(model.snapshot?.decisions.value?.first?.state, .needsAttention)
        XCTAssertNil(model.answeredDecisionID)
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
            findings: .unavailable("n/a"), roadmap: .unavailable("n/a"), decisions: .available([]),
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
        XCTAssertNil(model.trackerError)
        XCTAssertEqual(model.activeMilestone, "1.4")
    }

    func testAFailedTrackerWriteIsReported() async {
        let runner = FakeRunner(["gh issue edit 7 --repo owner/repo --remove-milestone": .failed(1, stderr: "HTTP 403\n")])
        let model = ProjectWindowModel(ref: .local(path: "/tmp/real"), source: FixedSource(snapshot: trackerSnapshot()),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        await model.performTrackerWrite(issue: 7, action: .backlog)
        XCTAssertEqual(model.trackerError?.contains("HTTP 403"), true)
        model.dismissTrackerError()
        XCTAssertNil(model.trackerError)
    }

    func testASampleProjectWritesNothingToTheTracker() async {
        let runner = FakeRunner()
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        await model.performTrackerWrite(issue: 42, action: .backlog)
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertNotNil(model.trackerError)
    }

    func testOpeningAnUnstartedCardShowsItsSheet() async {
        let model = await makeStudyHubModel()
        model.openTask("65")
        XCTAssertEqual(model.sheet, .unstartedTask("65"))
        XCTAssertEqual(model.lastOpenedTaskID, "65")
        XCTAssertEqual(model.selectedTaskID, "42", "the workspace behind the sheet is left as it was")
    }

    func testOpeningWorkThatHasStartedOpensTheWorkspace() async {
        let model = await makeStudyHubModel()
        model.openTask("57")
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.selectedTaskID, "57")
        XCTAssertEqual(model.tab, .activity)
    }

    func testDockingRunsOpensThePanel() async {
        let model = await makeStudyHubModel()
        model.dockRuns()
        XCTAssertTrue(model.runsOpen)
        XCTAssertTrue(model.runsDocked)
        model.floatRuns()
        XCTAssertTrue(model.runsOpen)
        XCTAssertFalse(model.runsDocked)
        model.toggleRuns()
        XCTAssertFalse(model.runsOpen)
    }

    func testRunsAndInsightsOpenIndependently() async {
        let model = await makeStudyHubModel()
        model.dockRuns()
        XCTAssertTrue(model.insightsOpen)
        model.toggleInsights()
        XCTAssertFalse(model.insightsOpen)
        XCTAssertTrue(model.runsOpen)
    }

    func testLinkRoutesToFinding() async {
        let model = await makeStudyHubModel()
        model.handle(.finding("F-093"))
        XCTAssertEqual(model.destination, .findings)
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
