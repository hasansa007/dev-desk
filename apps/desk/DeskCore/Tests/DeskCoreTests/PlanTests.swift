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

private struct WorkSource: ProjectDataSource {
    let tasks: [DeskTask]
    func load() async throws -> ProjectSnapshot {
        var s = ProjectSnapshot(project: ProjectInfo(name: "p", displayPath: "/p", branch: "main"), isDemo: false,
                                board: .available(tasks), boardNote: "", findings: .available(FindingsReport(runs: [], findings: [])),
                                roadmap: .unavailable("n/a"), connections: [], connectionsNote: "",
                                capabilities: CapabilityMatrix(providers: [], rows: [], note: ""), insights: .unavailable("none"),
                                activeMilestone: "Money")
        s.activeMilestoneReason = "top of Plan"
        return s
    }
}

/// ADR 0046 decision 13: Work — the milestone on the left chooses the Board on the right.
@MainActor
final class WorkScopeTests: XCTestCase {
    private func task(_ n: Int, _ labels: [String] = [], milestone: String? = nil) -> DeskTask {
        var t = DeskTask(id: String(n), issueNumber: n, title: "t", column: .backlog, headerBadge: StatusBadge(.neutral, ""),
                         branchLine: "", requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""),
                         parallel: .none(""))
        t.labels = labels
        t.milestone = milestone
        return t
    }

    func testTheDefaultIsTheWorkingMilestoneAndItCountsP0Elsewhere() async {
        let model = ProjectWindowModel(ref: .local(path: "/p"), source: WorkSource(tasks: [
            task(1, ["P1"], milestone: "Money"), task(2, ["P0"], milestone: "AI"), task(3, ["P0"]),
        ]), insightsDelay: .zero)
        await model.load()
        XCTAssertEqual(model.effectiveWorkScope, .milestone("Money"))
        XCTAssertEqual(model.tasks.filter(model.inWorkScope).map(\.issueNumber), [1])
        XCTAssertEqual(model.p0OutsideWorkScope, 2)
        model.workScope = .all
        XCTAssertEqual(model.p0OutsideWorkScope, 0, "All shows every P0 already")
        model.workScope = .noMilestone
        XCTAssertEqual(model.tasks.filter(model.inWorkScope).map(\.issueNumber), [3])
    }

    func testTheFirstColumnHoldsWhatHasNotStartedInTheSelection() async {
        var ready = task(1, ["P1"], milestone: "Money"); ready.column = .readyForDev
        var later = task(2, ["P2"], milestone: "AI"); later.column = .backlog
        var p0 = task(3, ["P0"], milestone: "AI"); p0.column = .readyForDev
        let model = ProjectWindowModel(ref: .local(path: "/p"), source: WorkSource(tasks: [ready, later, p0]), insightsDelay: .zero)
        await model.load()
        XCTAssertEqual(model.tasks.filter { model.inWorkColumn($0, .readyForDev) }.map(\.issueNumber), [1], "Working now")
        XCTAssertEqual(model.firstWorkColumnTitle, "Next up")
        model.workScope = .all
        XCTAssertEqual(model.tasks.filter { model.inWorkColumn($0, .readyForDev) }.map(\.issueNumber), [1, 3], "no backlog under All")
        model.workScope = .milestone("AI")
        XCTAssertEqual(model.tasks.filter { model.inWorkColumn($0, .readyForDev) }.map(\.issueNumber), [2, 3], "a waiting milestone's backlog")
        XCTAssertEqual(model.firstWorkColumnTitle, "Not started")
        XCTAssertEqual(model.workCounts(in: .readyForDev).total, 2)
    }

    func testTheSidebarListsWorkOnceAndRoadmapOpensWork() {
        XCTAssertEqual(Destination.sidebar, [.findings, .board, .terminals, .ideation, .diagrams])
        XCTAssertEqual(Destination.board.title, "Work")
        XCTAssertEqual(Destination.roadmap.title, "Work")
    }
}
