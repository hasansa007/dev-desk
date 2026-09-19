import XCTest
@testable import DeskCore

final class SequenceFlowsTests: XCTestCase {
    private func diagram(_ id: String, _ kind: String, views: [String] = [], at time: TimeInterval = 1) -> ArchDiagram {
        ArchDiagram(id: id, title: id, url: URL(fileURLWithPath: "/r/docs/arch/\(id).html"), kind: kind,
                    modifiedAt: Date(timeIntervalSince1970: time), views: views)
    }

    func testSlugs() {
        XCTAssertEqual(SequenceFlows.slug("Build a course"), "build-a-course")
        XCTAssertEqual(SequenceFlows.slug("  Pay — for a build! "), "pay-for-a-build")
        XCTAssertEqual(SequenceFlows.slug(fromKey: SequenceFlows.key("x-y")), "x-y")
        XCTAssertNil(SequenceFlows.slug(fromKey: "architecture"))
    }

    /// Every source counts the same, a flow two of them name is one row, and the newest drawing of each kind is read.
    func testSourcesAreEqualAndMerge() {
        let flows = SequenceFlows.list(diagrams: [
            diagram("old", "architecture", views: ["Stale path"], at: 1),
            diagram("new", "architecture", views: ["Build path", "Study path"], at: 2),
            diagram("flow", "dataflow", views: ["Build path"]),
        ], huntFlows: ["checkout-pay"])
        XCTAssertEqual(flows.map(\.name), ["Build path", "Study path", "Checkout pay"])
        XCTAssertEqual(flows[0].sources, [.architecture, .dataflow])
        XCTAssertEqual(flows[2].sources, [.hunt])
    }

    /// With no Architecture or Data flow drawn, the hunt alone lists the flows — any one source is enough.
    func testTheHuntAloneIsEnough() {
        XCTAssertEqual(SequenceFlows.list(diagrams: [], huntFlows: ["auth-session"]).map(\.slug), ["auth-session"])
    }

    /// A flow's drawing is matched by file name; a sequence no source names stays listed as drawn earlier.
    func testDrawingsAttachAndOrphansStay() {
        let flows = SequenceFlows.list(diagrams: [
            diagram("app", "architecture", views: ["Build path"]),
            diagram("app-sequence-build-path", "sequence"),
            diagram("studyhub-build-sequence", "sequence"),
        ], huntFlows: [])
        XCTAssertEqual(flows.first?.drawing?.id, "app-sequence-build-path")
        XCTAssertEqual(flows.last?.sources, [.drawn])
        XCTAssertEqual(flows.count, 2)
    }

    func testHuntFlowsAreReadFromThePerFlowTable() {
        let report = """
        Declared: 12 finders
        Per flow — findings · verified · duration · tokens · calls
          worker-queue      2 · 1 (C4)        1m38s    88k   15
          auth-session      2 · 2 (C1 ×2)     2m32s    93k   23   INCOMPLETE: not read
          arch recount      — · —             1m11s    71k    7
          checkers (26)     26 CONFIRMED

        ## FILED
          not-a-flow        1
        """
        XCTAssertEqual(SequenceFlows.huntFlows(in: report), ["worker-queue", "auth-session"])
    }
}
