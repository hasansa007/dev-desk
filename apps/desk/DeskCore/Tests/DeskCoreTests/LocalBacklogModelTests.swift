import XCTest
@testable import DeskCore

/// Re-reads the folder on every load, the way the real data source does, so a write shows up after a reload.
private struct FolderSource: ProjectDataSource {
    let root: String
    func load() async throws -> ProjectSnapshot {
        let items = LocalBacklog.read(projectPath: root)
        return ProjectSnapshot(project: ProjectInfo(name: "p", displayPath: root, branch: "main"), isDemo: false,
                               board: .available(BoardBuilder.build(BoardInput(localBacklog: items))), boardNote: "",
                               findings: .available(FindingsReport(runs: [], findings: [])), roadmap: .unavailable("n/a"),
                               connections: [], connectionsNote: "", capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                               insights: .unavailable("none"), localBacklog: items,
                               filedBacklogKeys: LocalBacklog.filedKeys(projectPath: root), repositoryRoot: root)
    }
}

@MainActor
final class LocalBacklogModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("backlog-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .local(path: root.path), source: FolderSource(root: root.path), insightsDelay: .zero)
        await model.load()
        return model
    }

    private let draft = BacklogDraft(key: "2026-08-31-C1", title: "Callback fetch returns 0", body: "## What\n\nIt returns early.",
                                     description: "Callback fetch returns 0.", area: "Logic", source: "dev:survey run 2026-08-31")

    /// Filing with no tracker puts a card on the board at once, and the finding knows it has been filed.
    func testFilingLocallyPutsACardOnTheBoard() async {
        let model = await makeModel()
        XCTAssertFalse(model.isInLocalBacklog(draft.key))

        await model.fileLocally(draft)

        XCTAssertTrue(model.isInLocalBacklog(draft.key))
        let card = model.tasks.first { $0.isLocalBacklog }
        XCTAssertEqual(card?.title, "Callback fetch returns 0")
        XCTAssertEqual(card?.column, .backlog)
        XCTAssertNil(model.writeFailure)
    }

    /// Promoted means GitHub owns it: the card goes, and the finding still counts as filed.
    func testAPromotedItemLeavesTheBoardButStaysFiled() async throws {
        let model = await makeModel()
        await model.fileLocally(draft)
        let entry = try XCTUnwrap(model.tasks.first { $0.isLocalBacklog }?.localBacklogID)

        await model.markLocalItemFiled(entry: entry, issue: 87)

        XCTAssertFalse(model.tasks.contains { $0.isLocalBacklog })
        XCTAssertTrue(model.isInLocalBacklog(draft.key), "a filed finding must not offer filing again")
    }

    func testRemovingAnItemTakesItsCardOffTheBoard() async throws {
        let model = await makeModel()
        await model.fileLocally(draft)
        let card = try XCTUnwrap(model.tasks.first { $0.isLocalBacklog })

        await model.removeLocalItem(card)

        XCTAssertFalse(model.tasks.contains { $0.isLocalBacklog })
        XCTAssertFalse(model.isInLocalBacklog(draft.key))
    }
}
