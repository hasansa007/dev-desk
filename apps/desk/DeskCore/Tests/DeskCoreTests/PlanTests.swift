import XCTest
@testable import DeskCore

/// ADR 0046 step 3: the Plan's order, Working now, and its rows.
final class PlanTests: XCTestCase {
    private func task(_ n: Int, _ labels: [String] = [], milestone: String? = nil, column: BoardColumn = .backlog) -> DeskTask {
        var t = DeskTask(id: String(n), issueNumber: n, title: "t\(n)", column: column, headerBadge: StatusBadge(.neutral, ""),
                         branchLine: "", requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""),
                         parallel: .none(""))
        t.labels = labels
        t.milestone = milestone
        return t
    }
    private func ms(_ title: String, _ closed: Int = 0, _ total: Int = 0) -> Milestone {
        Milestone(id: title, title: title, progress: 0, note: "", closed: closed, total: total)
    }
    private func gh(_ title: String, due: String? = nil, created: String) -> GitHubMilestone {
        GitHubMilestone(title: title, dueOn: due, createdAt: created)
    }

    // MARK: order

    func testMovingToTopKeepsTheRestOfTheShownOrder() {
        let moved = PlanOrder().movingToTop("C", shown: ["A", "B", "C"])
        XCTAssertEqual(moved.titles, ["C", "A", "B"])
        XCTAssertEqual(moved.movingToTop("B", shown: ["C", "A", "B"]).titles, ["B", "C", "A"])
    }

    func testApplyPutsStoredTitlesFirstAndKeepsTheRestInPlace() {
        let order = PlanOrder(titles: ["C", "gone"])
        XCTAssertEqual(order.apply(["A", "B", "C"], title: { $0 }), ["C", "A", "B"])
    }

    func testTheOrderRoundTripsThroughDevdesk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(PlanOrder.read(projectRoot: root), PlanOrder(), "missing reads as no order")
        PlanOrder(titles: ["X", "Y"]).write(projectRoot: root)
        XCTAssertEqual(PlanOrder.read(projectRoot: root).titles, ["X", "Y"])
    }

    // MARK: working now

    func testTheTopOfPlanWinsOverDueDates() {
        let milestones = [gh("Due soon", due: "2026-10-01T00:00:00Z", created: "2026-09-01"), gh("Chosen", created: "2026-09-02")]
        XCTAssertEqual(ActiveMilestone.resolve(milestones, order: ["Chosen"]).title, "Chosen")
        XCTAssertEqual(ActiveMilestone.resolve(milestones, order: ["Chosen"]).why, "top of Plan")
    }

    func testAClosedMilestoneInTheOrderIsSkippedAndNoOrderKeepsTheOldRule() {
        let milestones = [gh("A", created: "2026-09-01"), gh("B", created: "2026-09-02")]
        XCTAssertEqual(ActiveMilestone.resolve(milestones, order: ["Closed one", "B"]).title, "B")
        XCTAssertEqual(ActiveMilestone.resolve(milestones).title, "A", "oldest open, as before")
    }

    // MARK: rows

    func testRowsFollowTheOrderMarkWorkingNowAndSortByPriority() {
        let rows = PlanBuilder.rows(milestones: [ms("A", 1, 4), ms("B")], order: PlanOrder(titles: ["B"]), active: "B",
                                    tasks: [task(1, ["P3"], milestone: "B"), task(2, ["P0"], milestone: "B"), task(3, milestone: "A")])
        XCTAssertEqual(rows.map(\.title), ["B", "A"], "stored order first; no unplaced issues, so no No-milestone row")
        XCTAssertTrue(rows[0].isWorkingNow)
        XCTAssertEqual(rows[0].tasks.map(\.issueNumber), [2, 1], "P0 before P3")
        XCTAssertEqual(rows[1].closed, 1)
        XCTAssertEqual(rows[0].priorityCounts.map(\.priority), ["P0", "P3"])
    }

    func testUnplacedIssuesGetANoMilestoneRowAndDoneOnesAreLeftOut() {
        let rows = PlanBuilder.rows(milestones: [ms("A")], order: PlanOrder(), active: "A",
                                    tasks: [task(1), task(2, column: .done), task(3, milestone: "A")])
        XCTAssertNil(rows.last?.title)
        XCTAssertEqual(rows.last?.tasks.map(\.issueNumber), [1])
    }

    func testAFilterHidesRowsItEmptiesButNoFilterKeepsEmptyMilestones() {
        let tasks = [task(1, ["P1"], milestone: "A")]
        let all = PlanBuilder.rows(milestones: [ms("A"), ms("Empty")], order: PlanOrder(), active: "A", tasks: tasks)
        XCTAssertEqual(all.compactMap(\.title), ["A", "Empty"])
        let filtered = PlanBuilder.rows(milestones: [ms("A"), ms("Empty")], order: PlanOrder(), active: "A", tasks: tasks,
                                        filter: TaskFilter(priorities: ["P1"]))
        XCTAssertEqual(filtered.compactMap(\.title), ["A"])
    }
}
