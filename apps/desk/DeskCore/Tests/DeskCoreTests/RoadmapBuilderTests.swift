import XCTest
@testable import DeskCore

final class RoadmapBuilderTests: XCTestCase {
    private func issue(_ number: Int, _ title: String, labels: [String] = [], milestone: String? = nil) -> GitHubIssue {
        GitHubIssue(number: number, title: title, labels: labels.map { GitHubLabel(name: $0) },
                    milestone: milestone.map { GitHubIssue.MilestoneRef(title: $0) }, url: "https://github.com/acme/app/issues/\(number)")
    }

    private var roadmap: Roadmap {
        RoadmapBuilder.build(
            milestones: [
                GitHubMilestone(title: "Later", dueOn: nil, createdAt: "2026-01-01T00:00:00Z", openIssues: 1, closedIssues: 0),
                GitHubMilestone(title: "v3", dueOn: "2026-12-01T07:00:00Z", createdAt: "2026-03-01T00:00:00Z", openIssues: 2, closedIssues: 2),
                GitHubMilestone(title: "v2", dueOn: "2026-10-01T07:00:00Z", createdAt: "2026-05-01T00:00:00Z", openIssues: 1, closedIssues: 3),
                GitHubMilestone(title: "Empty", dueOn: nil, createdAt: "2026-06-01T00:00:00Z"),
            ],
            issues: [
                issue(1, "Export", labels: ["enhancement", "P2"], milestone: "v2"),
                issue(2, "Crash", labels: ["bug", "P1"], milestone: "v3"),
                issue(3, "Offline", labels: ["epic"], milestone: "v3"),
                issue(4, "Token leak", labels: ["security"], milestone: "v2"),
                issue(5, "Unplanned epic", labels: ["epic", "P3"]),
                issue(6, "Loose task"),
                issue(7, "Data loss", labels: ["critical"]),
                issue(8, "Someday idea", labels: ["feature"], milestone: "Later"),
                issue(9, "Chore", milestone: "v2"),
            ])
    }

    func testThemesFollowMilestonesByDueDateThenCreationWithCriticalAndUnscheduledApart() {
        let themes = roadmap.themes
        XCTAssertEqual(themes.map(\.title), ["Milestone · v2", "Milestone · v3", "Milestone · Later", "Milestone · Empty",
                                             "Not scheduled", "Critical concerns"])
        XCTAssertEqual(themes.map { $0.items.map(\.id) }, [["1", "9"], ["2", "3"], ["8"], [], ["5"], ["4", "7"]])
        XCTAssertEqual(themes.map(\.isCritical), [false, false, false, false, false, true])
    }

    func testItemsCarryWorkTypePriorityCommitmentAndABoardLink() {
        let items = Dictionary(roadmap.themes.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(items["1"], RoadmapItem(id: "1", title: "Export", workType: "Feature", priority: "P2", commitment: .committed,
                                               linkText: "Board: [#1](desk://task/1)"))
        XCTAssertEqual(items["2"].map { [$0.workType, $0.priority] }, ["Defect", "P1"])
        XCTAssertEqual(items["3"].map { [$0.workType, $0.priority] }, ["Epic", "Unprioritised"])
        XCTAssertEqual(items["8"]?.workType, "Feature")
        XCTAssertEqual(items["9"]?.workType, "Task")
        XCTAssertEqual(items["5"]?.commitment, .considered)
        XCTAssertEqual(items["4"].map { [$0.isCritical, $0.commitment == .committed] }, [true, true])
        XCTAssertEqual(items["7"].map { [$0.isCritical, $0.commitment == .considered] }, [true, true])
        XCTAssertNil(items["6"])
    }

    func testMilestonesReportProgressAndDueDate() {
        XCTAssertEqual(roadmap.milestones, [
            Milestone(id: "v2", title: "v2", progress: 0.75, note: "3 of 4 issues closed · due 2026-10-01", closed: 3, total: 4),
            Milestone(id: "v3", title: "v3", progress: 0.5, note: "2 of 4 issues closed · due 2026-12-01", closed: 2, total: 4),
            Milestone(id: "Later", title: "Later", progress: 0, note: "0 of 1 issues closed · no due date", closed: 0, total: 1),
            Milestone(id: "Empty", title: "Empty", progress: 0, note: "0 of 0 issues closed · no due date", closed: 0, total: 0),
        ])
    }

    func testNoteSaysWhereThemesComeFrom() {
        XCTAssertEqual(roadmap.note, "Themes are this repository's open milestones. Work type, priority and commitment come from labels and milestone membership.")
    }
}
