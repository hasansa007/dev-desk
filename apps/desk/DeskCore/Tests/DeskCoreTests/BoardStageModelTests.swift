import Foundation
import XCTest
@testable import DeskCore

/// Re-reads `.devdesk/board.json` on every load, the way `LocalGitDataSource` does, so a stage the model
/// writes shows up on the board after the reload the move itself triggers.
private struct StageSource: ProjectDataSource {
    let root: String
    func load() async throws -> ProjectSnapshot {
        let stages = BoardStages.read(projectRoot: URL(fileURLWithPath: root, isDirectory: true)).stages
        let github = GitHubData(slug: "acme/app", issues: [
            GitHubIssue(number: 42, title: "Answer everything", labels: [], milestone: nil,
                        updatedAt: "2026-09-01T00:00:00Z", body: "", url: "https://github.com/acme/app/issues/42"),
        ])
        return ProjectSnapshot(project: ProjectInfo(name: "p", displayPath: root, branch: "main"), isDemo: false,
                               board: .available(BoardBuilder.build(BoardInput(github: github, stages: stages))), boardNote: "",
                               findings: .available(FindingsReport(runs: [], findings: [])), roadmap: .unavailable("n/a"),
                               connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                               insights: .unavailable("none"), repositoryRoot: root)
    }
}

@MainActor
final class BoardStageModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .local(path: root.path), source: StageSource(root: root.path), insightsDelay: .zero)
        await model.load()
        return model
    }

    private func card(_ model: ProjectWindowModel) throws -> DeskTask {
        try XCTUnwrap(model.task("42"))
    }

    /// A task built the way the board really builds one: a branch git holds In progress by its commits.
    private func branchedTask(unmerged: Int) -> DeskTask {
        DeskTask(id: "12", issueNumber: 12, title: "Committed work", column: .inProgress,
                 headerBadge: StatusBadge(.neutral, "3 commits ahead"), branchLine: "feat/x", branch: "feat/x",
                 requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""),
                 parallel: .none(""), unmergedCount: unmerged)
    }

    func testMoveToReadyForDevPutsTheCardThereAndStoresTheStage() async throws {
        let model = await makeModel()
        XCTAssertEqual(try card(model).column, .backlog)

        await model.moveToReadyForDev(try card(model))

        XCTAssertEqual(try card(model).column, .readyForDev)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, ["42": .readyForDev])
        XCTAssertNil(model.writeFailure)
    }

    func testReturnToBacklogClearsTheStage() async throws {
        let model = await makeModel()
        await model.moveToReadyForDev(try card(model))

        await model.returnToBacklog(try card(model))

        XCTAssertEqual(try card(model).column, .backlog)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, [:], "Backlog is the absence of a stage, not a stage")
    }

    /// A start moves the card at once, instead of waiting for git to see a commit.
    func testRecordStartedMovesTheCardToInProgress() async throws {
        let model = await makeModel()
        await model.recordStarted(try card(model))
        XCTAssertEqual(try card(model).column, .inProgress)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, ["42": .inProgress])
    }

    /// A Start with every agent slot busy parks the card (ADR 0035): the stage is the queue.
    func testQueueForStartPutsTheCardInQueued() async throws {
        let model = await makeModel()
        await model.queueForStart(try card(model))
        XCTAssertEqual(try card(model).column, .queued)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, ["42": .queued])
    }

    func testCancelToReadyForDevStepsAStartedCardBack() async throws {
        let model = await makeModel()
        await model.recordStarted(try card(model))

        await model.cancelToReadyForDev(try card(model))

        XCTAssertEqual(try card(model).column, .readyForDev)
    }

    /// git owns In progress once commits exist (ADR 0011): the move is refused with the reason, and the
    /// stored stages are left exactly as they were — a write that changed nothing would still be a lie.
    func testCancelIsRefusedOnceCommitsExist() async {
        let model = await makeModel()
        let branched = branchedTask(unmerged: 3)

        XCTAssertEqual(model.stageBackBlockedReason(for: branched),
                       "It has 3 commits on feat/x — git decides In progress, so this would not move it.")
        await model.cancelToReadyForDev(branched)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, [:])

        XCTAssertNil(model.stageBackBlockedReason(for: branchedTask(unmerged: 0)), "zero commits is git saying nothing yet")
    }

    /// A `branch:`/`pr:`/`merged:` card is git's own: asking to stage one writes nothing.
    func testAGitOwnedCardTakesNoStage() async {
        let model = await makeModel()
        for id in ["branch:spike/z", "pr:20", "merged:9"] {
            var task = branchedTask(unmerged: 0)
            task.id = id
            await model.moveToReadyForDev(task)
        }
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, [:])
    }

    /// The rule that answers the original report: a task with something live in this window is never shown
    /// as unstarted — Backlog with a pulsing "Running" pill cannot happen.
    func testARunningTaskIsNeverShownInAnUnstartedColumn() {
        for column in [BoardColumn.backlog, .readyForDev, .queued] {
            var task = branchedTask(unmerged: 0)
            task.column = column
            XCTAssertEqual(ProjectWindowModel.promoted(task, isRunning: true).column, .inProgress, "\(column)")
            XCTAssertEqual(ProjectWindowModel.promoted(task, isRunning: false).column, column, "an idle card stays put")
        }
        // The columns git owns are never touched: the promotion only fills, it never contradicts.
        for column in [BoardColumn.inProgress, .review, .done] {
            var task = branchedTask(unmerged: 0)
            task.column = column
            XCTAssertEqual(ProjectWindowModel.promoted(task, isRunning: true).column, column, "\(column)")
        }
    }
}
