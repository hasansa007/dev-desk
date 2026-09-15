import XCTest
@testable import DeskCore

/// Re-reads the folder and `.devdesk/board.json` on every load, the way `LocalGitDataSource` does, so a
/// task typed on the board shows up — in its column — after the reload the add itself triggers.
private struct BoardSource: ProjectDataSource {
    let root: String
    func load() async throws -> ProjectSnapshot {
        let items = LocalBacklog.read(projectPath: root)
        let stages = BoardStages.read(projectRoot: URL(fileURLWithPath: root, isDirectory: true)).stages
        return ProjectSnapshot(project: ProjectInfo(name: "p", displayPath: root, branch: "main"), isDemo: false,
                               board: .available(BoardBuilder.build(BoardInput(localBacklog: items, stages: stages))), boardNote: "",
                               findings: .available(FindingsReport(runs: [], findings: [])), roadmap: .unavailable("n/a"),
                               connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                               insights: .unavailable("none"), localBacklog: items,
                               filedBacklogKeys: LocalBacklog.filedKeys(projectPath: root), repositoryRoot: root)
    }
}

@MainActor
final class AddTaskModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("add-task-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .local(path: root.path), source: BoardSource(root: root.path), insightsDelay: .zero)
        await model.load()
        return model
    }

    private func backlogFiles() -> [String] {
        let directory = root.appendingPathComponent(LocalBacklog.folder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
    }

    func testAddingFromBacklogWritesOneFileAndTheCardLandsInBacklog() async throws {
        let model = await makeModel()

        let added = await model.addTask(title: "Fix the callback fetch", notes: "It returns early.", column: .backlog)

        XCTAssertTrue(added)
        XCTAssertEqual(backlogFiles().count, 1)
        let item = try XCTUnwrap(LocalBacklog.read(projectPath: root.path).first)
        XCTAssertEqual(item.title, "Fix the callback fetch", "the front matter carries the typed title")
        let card = try XCTUnwrap(model.tasks.first { $0.isLocalBacklog })
        XCTAssertEqual(card.column, .backlog)
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, [:], "Backlog is the absence of a stage, not a stage")
        XCTAssertNil(model.writeFailure)
    }

    func testAddingFromReadyForDevRecordsTheStageAndTheCardLandsThere() async throws {
        let model = await makeModel()

        let added = await model.addTask(title: "Ship the exporter", notes: "", column: .readyForDev)

        XCTAssertTrue(added)
        XCTAssertEqual(backlogFiles().count, 1)
        let card = try XCTUnwrap(model.tasks.first { $0.isLocalBacklog })
        XCTAssertEqual(card.column, .readyForDev, "the first board after the add already shows the card where it was typed")
        XCTAssertEqual(BoardStages.read(projectRoot: root).stages, [card.id: .readyForDev])
        XCTAssertNil(model.writeFailure)
    }

    func testABlankTitleWritesNothing() async {
        let model = await makeModel()
        for title in ["", "   ", "\n\t "] {
            let added = await model.addTask(title: title, notes: "some notes", column: .backlog)
            XCTAssertFalse(added, "'\(title)'")
        }
        XCTAssertEqual(backlogFiles(), [])
        XCTAssertFalse(model.tasks.contains { $0.isLocalBacklog })
    }

    /// `LocalBacklog.write` never overwrites and silently returns the existing path — from the board that
    /// would look like a press that did nothing, so the model refuses aloud instead.
    func testASecondTaskWithTheSameTitleOnTheSameDayIsRefused() async throws {
        let model = await makeModel()
        let first = await model.addTask(title: "Fix the callback fetch", notes: "first", column: .backlog)
        XCTAssertTrue(first)
        let firstFiles = backlogFiles()

        let added = await model.addTask(title: "Fix the callback fetch", notes: "second", column: .backlog)

        XCTAssertFalse(added)
        XCTAssertEqual(backlogFiles(), firstFiles, "no second file is written")
        let failure = try XCTUnwrap(model.writeFailure)
        let fileName = try XCTUnwrap(firstFiles.first)
        XCTAssertTrue(Markdown.unescape(failure.message).contains(fileName), "the failure names the file: \(failure.message)")
    }

    func testASampleProjectWritesNothing() async {
        let model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub), insightsDelay: .zero)
        await model.load()

        let added = await model.addTask(title: "Anything at all", notes: "", column: .backlog)

        XCTAssertFalse(added, "a sample has no repository root, so there is nowhere to write")
    }

    func testNotesBecomeTheEntrysBodyAndReadBack() async throws {
        let model = await makeModel()
        let added = await model.addTask(title: "Keep the notes", notes: "## What\n\nIt drops events on resume.", column: .backlog)

        XCTAssertTrue(added)
        let item = try XCTUnwrap(LocalBacklog.read(projectPath: root.path).first)
        XCTAssertEqual(item.body, "## What\n\nIt drops events on resume.")
        let card = try XCTUnwrap(model.tasks.first { $0.isLocalBacklog })
        XCTAssertEqual(card.requirements.value?.body, "## What\n\nIt drops events on resume.")
    }

    func testEmptyNotesStillMakeAValidReadableEntry() async throws {
        let model = await makeModel()
        let added = await model.addTask(title: "No notes yet", notes: "", column: .backlog)

        XCTAssertTrue(added)
        let item = try XCTUnwrap(LocalBacklog.read(projectPath: root.path).first)
        XCTAssertEqual(item.title, "No notes yet")
        XCTAssertEqual(item.body, "")
        XCTAssertEqual(model.tasks.first { $0.isLocalBacklog }?.title, "No notes yet")
    }
}
