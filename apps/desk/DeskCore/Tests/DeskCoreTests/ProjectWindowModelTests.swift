import XCTest
@testable import DeskCore

@MainActor
final class ProjectWindowModelTests: XCTestCase {
    private func makeStudyHubModel() async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub), insightsDelay: .zero)
        await model.load()
        return model
    }

    /// A real folder, so the containment check resolves the same symlinks for the root and the file under it.
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("window-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

    /// Closing one and opening another must not hand out an id that is already on screen: two rows with one
    /// id collide in the list and in the session registry, and the new terminal draws the old one's frame.
    func testAClosedTerminalsIdIsNeverHandedOutAgain() async {
        let model = await makeStudyHubModel()
        let first = model.newTerminal()
        let second = model.newTerminal()
        model.closeTerminal(first)
        let third = model.newTerminal()

        XCTAssertNotEqual(third, second)
        XCTAssertNotEqual(third, first)
        XCTAssertEqual(model.scratchTerminals, [second, third])
        XCTAssertEqual(Set(model.scratchTerminals).count, model.scratchTerminals.count)
    }

    /// A scratch session is in front the moment it is opened, and is forgotten with its row.
    func testAScratchSessionIsSelectedWhenItOpensAndForgottenWhenItCloses() async {
        let model = await makeStudyHubModel()
        let first = model.newTerminal()
        let second = model.newTerminal()

        XCTAssertEqual(model.selectedSessionID, second)

        model.closeTerminal(second)
        XCTAssertEqual(model.scratchTerminals, [first])
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
        model.go(.findings)
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

    func testOpeningFilesStartsItAtTheMinimumWidth() async {
        let model = await makeStudyHubModel()
        model.filesWidth = 640

        model.showFiles()
        XCTAssertTrue(model.filesOpen)
        XCTAssertEqual(model.filesWidth, ProjectWindowModel.filesWidthMin)

        model.filesWidth = 700
        model.showFiles()
        XCTAssertEqual(model.filesWidth, 700, "asking for a panel already open leaves the width you gave it")

        model.toggleFiles()
        XCTAssertFalse(model.filesOpen)
        model.toggleFiles()
        XCTAssertTrue(model.filesOpen)
        XCTAssertEqual(model.filesWidth, ProjectWindowModel.filesWidthMin, "reopening starts at the floor again")
    }

    func testSelectedFileURLIsTheAbsolutePathUnderTheRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ProjectWindowModel(ref: .local(path: root.path), source: FixedSource(snapshot: trackerSnapshot()),
                                       insightsDelay: .zero)
        model.selectedFilePath = "docs/adr/0001-decision.md"

        let url = try XCTUnwrap(model.selectedFileURL)
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, root.appendingPathComponent("docs/adr/0001-decision.md").standardizedFileURL.path)
        XCTAssertTrue(url.absoluteString.hasPrefix("file:///"), "a relative URL is not something the system can open")
    }

    func testAPathThatEscapesTheRootHasNoURLAndIsReportedNotIgnored() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(ProjectWindowModel.fileURL(root: root, relativePath: "../outside.md"))
        XCTAssertNil(ProjectWindowModel.fileURL(root: root, relativePath: "/etc/hosts"), "an absolute id is not a relative path")
        XCTAssertNil(ProjectWindowModel.fileURL(root: root, relativePath: "  "))

        let model = ProjectWindowModel(ref: .local(path: root.path), source: FixedSource(snapshot: trackerSnapshot()),
                                       insightsDelay: .zero)
        model.selectedFilePath = "../outside.md"
        XCTAssertNil(model.selectedFileURL)
        model.openSelectedFile()
        XCTAssertEqual(model.writeFailure?.title, "The file was not opened")
    }

    func testClosingTheFileClearsTheSelectionOnly() async {
        let model = await makeStudyHubModel()
        model.showFiles()
        model.selectedFilePath = "README.md"

        model.closeFile()
        XCTAssertNil(model.selectedFilePath)
        XCTAssertTrue(model.filesOpen, "dismissing the viewer never closes the tree it was opened from")
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

    // MARK: - Roadmap waits on Findings

    /// No report, an empty one, or a run still going: Roadmap is refused with the reason. A finished report frees it.
    func testRoadmapWaitsForAFinishedFindingsReport() {
        let empty = FindingsReport(runs: [], findings: [])
        XCTAssertNotNil(ProjectWindowModel.roadmapBlockedReason(findings: nil, findingsInProgress: false))
        XCTAssertNotNil(ProjectWindowModel.roadmapBlockedReason(findings: .unavailable("no folder"), findingsInProgress: false))
        XCTAssertTrue(ProjectWindowModel.roadmapBlockedReason(findings: .available(empty), findingsInProgress: false)?
            .contains("no findings yet") ?? false)
        let sample = SampleData.studyHubFindings()
        XCTAssertFalse(sample.runs.isEmpty)
        XCTAssertNil(ProjectWindowModel.roadmapBlockedReason(findings: .available(sample), findingsInProgress: false))
        XCTAssertTrue(ProjectWindowModel.roadmapBlockedReason(findings: .available(sample), findingsInProgress: true)?
            .contains("still running") ?? false)
    }

    /// Waiting holds while Findings runs and, once it finishes with a report, opens Roadmap's start sheet — it never
    /// starts the run itself. Cancelling ends the wait with nothing opened.
    @MainActor
    func testRoadmapAfterFindingsOpensTheStartSheetOnceFindingsFinishes() async {
        let model = await makeStudyHubModel()
        var running = true
        model.runRoadmapAfterFindings(findingsInProgress: { running }, poll: .milliseconds(10))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(model.roadmapWaitingForFindings)
        XCTAssertNil(model.sheet)
        running = false
        await model.roadmapWaitingForFindings?.value
        XCTAssertNil(model.roadmapWaitingForFindings)
        XCTAssertEqual(model.sheet, .runFocus("roadmap"))

        model.dismissSheet()
        running = true
        model.runRoadmapAfterFindings(findingsInProgress: { running }, poll: .milliseconds(10))
        model.cancelRoadmapAfterFindings()
        XCTAssertNil(model.roadmapWaitingForFindings)
        XCTAssertNil(model.sheet)
    }

    // MARK: - Diagram generation state

    /// Starting a generate marks the kind as generating and clears any earlier failure; the kind is remembered
    /// by its session id so its end clears the right spinner.
    func testBeginningAGenerateMarksTheKindAndClearsAnyFailure() async {
        let model = await makeStudyHubModel()
        model.beginGeneratingDiagram(kind: "architecture", sessionID: "term:1")
        XCTAssertTrue(model.isGeneratingDiagram(kind: "architecture"))
        XCTAssertNil(model.diagramGenerateFailure(kind: "architecture"))
        XCTAssertEqual(model.finishGeneratingDiagram(sessionID: "term:1"), "architecture")
        XCTAssertFalse(model.isGeneratingDiagram(kind: "architecture"))
        XCTAssertNil(model.finishGeneratingDiagram(sessionID: "term:1"), "a session is only finished once")
    }

    /// An interactive run stays open after it draws, so the pick-up is what ends a generate. With no drawing newer
    /// than the start, nothing is finished and the spinner stays — a sample has no folder, so it never has one.
    func testPickUpLeavesAKindGeneratingUntilItsDrawingLands() async {
        let model = await makeStudyHubModel()
        model.beginGeneratingDiagram(kind: "workflow", sessionID: "term:3")
        XCTAssertEqual(model.pickUpGeneratedDiagrams(), [])
        XCTAssertTrue(model.isGeneratingDiagram(kind: "workflow"))
    }

    /// A generate that drew nothing records a reason for the pane, so a refusal is visible instead of a silent
    /// revert — and it carries the session id, since the session is kept as the run's readable evidence. A
    /// sample has no folder, so its `diagram(kind:)` is always nil — the failure path.
    func testAGenerateThatDrawsNothingRecordsAReason() async {
        let model = await makeStudyHubModel()
        model.beginGeneratingDiagram(kind: "dataflow", sessionID: "term:2")
        _ = model.finishGeneratingDiagram(sessionID: "term:2")
        model.recordDiagramGenerateResult(kind: "dataflow", sessionID: "term:2")
        let failure = model.diagramGenerateFailure(kind: "dataflow")
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure?.message.contains("without drawing") ?? false, failure?.message ?? "nil")
        XCTAssertEqual(failure?.sessionID, "term:2", "the banner opens the kept session by this id")
    }

    /// The failure note leads with the run's own last line, and an immediate exit reads as a launch failure
    /// rather than a refusal — the swallowed-prompt bug spent its life mislabelled "it may have declined".
    func testAnImmediateExitReadsAsALaunchFailureLedByTheRunsOwnWords() {
        let message = ProjectWindowModel.diagramFailureMessage(
            lastLine: "Error: Input must be provided either through stdin or as a prompt argument when using --print",
            exitStatus: 1, duration: 2)
        XCTAssertTrue(message.hasPrefix("The run ended saying: `Error: Input must be provided"), message)
        XCTAssertTrue(message.contains("(exit 1)"), message)
        XCTAssertTrue(message.contains("launch failure"), message)
        XCTAssertFalse(message.contains("declined"), "a run that never ran must not be called a refusal")
    }

    /// A run that took its time and still drew nothing keeps the honest guess: it may really have declined.
    func testARunThatTookItsTimeKeepsTheDeclinedWording() {
        let slow = ProjectWindowModel.diagramFailureMessage(lastLine: nil, exitStatus: 0, duration: 300)
        XCTAssertTrue(slow.contains("may have declined"), slow)
        let unknown = ProjectWindowModel.diagramFailureMessage(lastLine: nil, exitStatus: nil, duration: nil)
        XCTAssertTrue(unknown.contains("may have declined"), "no timing reads as the slow case, never as a launch verdict")
    }

    // MARK: - Diagram repo state (git setup offer)

    private func repoStateModel(repositoryRoot: String?, headRevision: String?, remote: String? = nil) async -> ProjectWindowModel {
        let snapshot = ProjectSnapshot(
            project: ProjectInfo(name: "P", displayPath: "~/p", branch: "main", remote: remote, headRevision: headRevision),
            isDemo: false, board: .available([]), boardNote: "",
            findings: .available(FindingsReport(runs: [], findings: [])), roadmap: .unavailable("n/a"),
            connections: [], connectionsNote: "",
            capabilities: CapabilityMatrix(providers: [], rows: [], note: ""), insights: .unavailable("n/a"),
            repositoryRoot: repositoryRoot)
        let model = ProjectWindowModel(ref: .local(path: "/tmp/p"), source: FixedSource(snapshot: snapshot), insightsDelay: .zero)
        await model.load()
        return model
    }

    /// The gates in turn: not a repo, then no commit, then no remote (architecture only — its evidence needs a
    /// GitHub origin), then ready.
    /// A sample has no folder to draw from and reads as ready (blocked elsewhere by its own reason).
    func testDiagramRepoStateReflectsGitSetup() async {
        let notRepo = await repoStateModel(repositoryRoot: nil, headRevision: nil)
        XCTAssertEqual(notRepo.diagramRepoState(kind: "architecture"), .notARepository)

        let noCommits = await repoStateModel(repositoryRoot: "/tmp/p", headRevision: nil)
        XCTAssertEqual(noCommits.diagramRepoState(kind: "architecture"), .noCommits)

        let noRemote = await repoStateModel(repositoryRoot: "/tmp/p", headRevision: "a1b2c3d", remote: nil)
        XCTAssertEqual(noRemote.diagramRepoState(kind: "architecture"), .noRemote)
        XCTAssertEqual(noRemote.diagramRepoState(kind: "workflow"), .ready, "only architecture carries evidence")

        let ready = await repoStateModel(repositoryRoot: "/tmp/p", headRevision: "a1b2c3d", remote: "github.com/o/r")
        XCTAssertEqual(ready.diagramRepoState(kind: "architecture"), .ready)

        let sample = await makeStudyHubModel()
        XCTAssertEqual(sample.diagramRepoState(kind: "architecture"), .ready, "a sample is blocked by its own reason, not the git offer")
    }

    /// Adding a remote only acts on a committed repo that has none: a ready repo is left alone and reports false.
    func testAddGitRemoteOnlyActsOnANoRemoteRepo() async {
        let ready = await repoStateModel(repositoryRoot: "/tmp/p", headRevision: "a1b2c3d", remote: "github.com/o/r")
        let did = await ready.addGitRemote(url: "https://github.com/o/r")
        XCTAssertFalse(did, "a repo that already has a remote is left alone")
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
