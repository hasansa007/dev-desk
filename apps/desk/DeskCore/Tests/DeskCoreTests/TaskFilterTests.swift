import XCTest
@testable import DeskCore

/// ADR 0046: one filter for the Board and the Plan.
final class TaskFilterTests: XCTestCase {
    private func task(_ number: Int?, labels: [String] = [], milestone: String? = nil, id: String? = nil) -> DeskTask {
        var t = DeskTask(id: id ?? number.map(String.init) ?? "branch:x", issueNumber: number, title: "t", column: .backlog,
                         headerBadge: StatusBadge(.neutral, "Backlog"), branchLine: "",
                         requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""), parallel: .none(""))
        t.labels = labels
        t.milestone = milestone
        return t
    }

    func testAnEmptyFilterMatchesEverything() {
        XCTAssertFalse(TaskFilter().isActive)
        XCTAssertTrue(TaskFilter().matches(task(nil)))
    }

    func testPriorityIsTheHighestLabelAndUnlabelledHasItsOwnChip() {
        XCTAssertEqual(task(1, labels: ["P2", "P0"]).priority, "P0")
        XCTAssertNil(task(1).priority)
        let f = TaskFilter(priorities: [TaskFilter.unprioritised])
        XCTAssertTrue(f.matches(task(1)))
        XCTAssertFalse(f.matches(task(2, labels: ["P1"])))
    }

    func testMilestoneAndNoMilestone() {
        XCTAssertTrue(TaskFilter(milestone: "Money").matches(task(1, milestone: "Money")))
        XCTAssertFalse(TaskFilter(milestone: "Money").matches(task(1, milestone: "Other")))
        XCTAssertTrue(TaskFilter(milestone: TaskFilter.noMilestone).matches(task(1)))
        XCTAssertFalse(TaskFilter(milestone: TaskFilter.noMilestone).matches(task(1, milestone: "Money")))
    }

    func testKindFromLabels() {
        XCTAssertEqual(task(1, labels: ["epic", "bug"]).kind, .epic)
        XCTAssertEqual(task(1, labels: ["bug"]).kind, .bug)
        XCTAssertEqual(task(1, labels: ["enhancement"]).kind, .feature)
        XCTAssertTrue(TaskFilter(kinds: [.bug]).matches(task(1, labels: ["bug"])))
        XCTAssertFalse(TaskFilter(kinds: [.bug]).matches(task(1, labels: ["task"])))
    }

    func testTagsMatchAny() {
        let f = TaskFilter(tags: ["security", "payments"])
        XCTAssertTrue(f.matches(task(1, labels: ["payments"])))
        XCTAssertFalse(f.matches(task(1, labels: ["bug"])))
        XCTAssertEqual(task(1, labels: ["payments", "bug", "security"]).tags, ["security", "payments"])
    }

    func testAnActiveFilterLeavesOutCardsWithNoIssue() {
        XCTAssertFalse(TaskFilter(priorities: ["P1"]).matches(task(nil)), "a branch or PR card has no priority to match")
    }

    func testFiltersCombineWithAnd() {
        let f = TaskFilter(milestone: "Money", priorities: ["P1"], tags: ["payments"])
        XCTAssertTrue(f.matches(task(1, labels: ["P1", "payments"], milestone: "Money")))
        XCTAssertFalse(f.matches(task(2, labels: ["P2", "payments"], milestone: "Money")))
    }
}
