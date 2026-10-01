import XCTest
@testable import DeskCore

final class CardOrderTests: XCTestCase {
    private func card(_ id: String) -> DeskTask {
        DeskTask(id: id, title: id, column: .readyForDev, headerBadge: StatusBadge(.neutral, id), branchLine: "", requirements: .unavailable(""), changes: .unavailable(""),
                 evidence: .unavailable(""), parallel: .none(""))
    }

    func testADroppedCardLandsAboveItsTargetAndTheWholeColumnIsStored() {
        let order = CardOrder().moving("c", before: "a", shown: ["a", "b", "c"])
        XCTAssertEqual(order.ids, ["c", "a", "b"])
        XCTAssertEqual(CardOrder().moving("a", before: nil, shown: ["a", "b", "c"]).ids, ["b", "c", "a"], "no target is the end")
    }

    func testStoredCardsLeadAndANewCardKeepsItsAutomaticPlaceAfterThem() {
        let tasks = ["new", "a", "b"].map(card)
        XCTAssertEqual(CardOrder(ids: ["b", "a", "gone"]).apply(tasks).map(\.id), ["b", "a", "new"])
    }

    func testTheOrderSurvivesAWriteAndAMissingFileReadsAsNone() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(CardOrder.read(projectRoot: root), CardOrder())
        CardOrder(ids: ["b", "a"]).write(projectRoot: root)
        XCTAssertEqual(CardOrder.read(projectRoot: root).ids, ["b", "a"])
    }
}
