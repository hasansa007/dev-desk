import XCTest
@testable import DeskCore

final class ActiveMilestoneTests: XCTestCase {
    func testNearestDueDateWins() {
        let result = ActiveMilestone.resolve([
            GitHubMilestone(title: "v3", dueOn: "2026-11-01T07:00:00Z", createdAt: "2026-01-01T00:00:00Z"),
            GitHubMilestone(title: "v2", dueOn: "2026-10-01T07:00:00Z", createdAt: "2026-02-01T00:00:00Z"),
            GitHubMilestone(title: "Someday", dueOn: nil, createdAt: "2025-01-01T00:00:00Z"),
        ])
        XCTAssertEqual(result.title, "v2")
        XCTAssertEqual(result.why, "nearest due date (2026-10-01)")
    }

    func testSameDayTieResolvesToNilNamingBoth() {
        let result = ActiveMilestone.resolve([
            GitHubMilestone(title: "v2", dueOn: "2026-10-01T07:00:00Z"),
            GitHubMilestone(title: "v2.1", dueOn: "2026-10-01T20:00:00Z"),
            GitHubMilestone(title: "v3", dueOn: "2026-12-01T07:00:00Z"),
        ])
        XCTAssertNil(result.title)
        XCTAssertEqual(result.why, "v2 and v2.1 are due the same day")
    }

    func testUndatedMilestonesFallBackToTheOldest() {
        let result = ActiveMilestone.resolve([
            GitHubMilestone(title: "B", createdAt: "2026-03-01T00:00:00Z"),
            GitHubMilestone(title: "A", createdAt: "2026-01-01T00:00:00Z"),
        ])
        XCTAssertEqual(result.title, "A")
        XCTAssertEqual(result.why, "oldest open milestone; none has a due date")
    }

    func testNoMilestoneResolvesToNil() {
        let result = ActiveMilestone.resolve([])
        XCTAssertNil(result.title)
        XCTAssertEqual(result.why, "no open milestone")
    }
}
