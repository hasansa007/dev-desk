import XCTest
@testable import DeskCore

final class GitHubDecodingTests: XCTestCase {
    func testIssuesDecodeLabelsMilestoneAndBody() throws {
        let json = """
        [{"body":"Fix it\\r\\n- [ ] one","labels":[{"id":"L1","name":"bug","description":"","color":"d73a4a"},{"id":"L2","name":"P1","description":"","color":"000000"}],"milestone":{"number":2,"title":"v2","description":"","dueOn":"2026-10-01T00:00:00Z"},"number":12,"title":"Crash on launch","updatedAt":"2026-09-01T10:00:00Z","url":"https://github.com/acme/app/issues/12"},
         {"body":"","labels":[],"milestone":null,"number":13,"title":"Docs","updatedAt":"2026-09-02T10:00:00Z","url":"https://github.com/acme/app/issues/13"}]
        """
        let issues = try XCTUnwrap(GitHubJSON.decode([GitHubIssue].self, from: json))
        XCTAssertEqual(issues.map(\.number), [12, 13])
        XCTAssertEqual(issues[0].labelNames, ["bug", "P1"])
        XCTAssertEqual(issues[0].milestone?.title, "v2")
        XCTAssertEqual(issues[0].body, "Fix it\r\n- [ ] one")
        XCTAssertNil(issues[1].milestone)
    }

    func testOpenPullRequestsDecodeReviewDecisionAndDraft() throws {
        let json = """
        [{"body":"Closes #12","headRefName":"gh-12-x","isDraft":false,"number":20,"reviewDecision":"CHANGES_REQUESTED","title":"Fix crash","url":"https://github.com/acme/app/pull/20"},
         {"body":"","headRefName":"spike","isDraft":true,"number":21,"reviewDecision":"","title":"Spike","url":"https://github.com/acme/app/pull/21"}]
        """
        let prs = try XCTUnwrap(GitHubJSON.decode([GitHubPullRequest].self, from: json))
        XCTAssertEqual(prs[0].reviewDecision, "CHANGES_REQUESTED")
        XCTAssertEqual(prs[0].headRefName, "gh-12-x")
        XCTAssertTrue(prs[1].isDraft)
        XCTAssertEqual(prs[1].reviewDecision, "")
    }

    func testMergedPullRequestsDecode() throws {
        let json = """
        [{"headRefName":"feature/tracker","mergedAt":"2026-09-11T07:07:04Z","number":49,"title":"feat: tracker","url":"https://github.com/acme/app/pull/49"}]
        """
        let merged = try XCTUnwrap(GitHubJSON.decode([GitHubMergedPullRequest].self, from: json))
        XCTAssertEqual(merged, [GitHubMergedPullRequest(number: 49, title: "feat: tracker", headRefName: "feature/tracker",
                                                        mergedAt: "2026-09-11T07:07:04Z", url: "https://github.com/acme/app/pull/49")])
    }

    func testMilestonesDecodeFromTheRESTShape() throws {
        let json = """
        [{"url":"https://api.github.com/repos/acme/app/milestones/1","number":1,"title":"v2","description":null,"creator":{"login":"octo"},
          "open_issues":3,"closed_issues":1,"state":"open","created_at":"2026-08-01T10:00:00Z","updated_at":"2026-09-01T10:00:00Z","due_on":"2026-10-01T07:00:00Z","closed_at":null},
         {"number":2,"title":"Someday","open_issues":0,"closed_issues":0,"state":"open","created_at":"2026-07-01T10:00:00Z","due_on":null}]
        """
        let milestones = try XCTUnwrap(GitHubJSON.decode([GitHubMilestone].self, from: json))
        XCTAssertEqual(milestones, [
            GitHubMilestone(title: "v2", dueOn: "2026-10-01T07:00:00Z", createdAt: "2026-08-01T10:00:00Z", openIssues: 3, closedIssues: 1),
            GitHubMilestone(title: "Someday", dueOn: nil, createdAt: "2026-07-01T10:00:00Z", openIssues: 0, closedIssues: 0),
        ])
    }

    func testChecksDecodeNameBucketAndLink() throws {
        let json = """
        [{"bucket":"pass","link":"https://github.com/acme/app/actions/runs/1","name":"unit"},{"bucket":"pending","link":"","name":"e2e"}]
        """
        let checks = try XCTUnwrap(GitHubJSON.decode([GitHubCheck].self, from: json))
        XCTAssertEqual(checks.map(\.name), ["unit", "e2e"])
        XCTAssertEqual(checks.map(\.bucket), ["pass", "pending"])
    }

    func testUnreadableJSONDecodesToNil() {
        XCTAssertNil(GitHubJSON.decode([GitHubIssue].self, from: "no checks reported on the 'x' branch"))
    }

    func testAuthStatusAccountLine() {
        let current = """
        github.com
          ✓ Logged in to github.com account hasansa007 (keyring)
          - Active account: true
        """
        XCTAssertEqual(GitHubJSON.account(fromAuthStatus: current), "hasansa007")
        XCTAssertEqual(GitHubJSON.account(fromAuthStatus: "  ✓ Logged in to github.com as octo (oauth_token)"), "octo")
        XCTAssertNil(GitHubJSON.account(fromAuthStatus: "You are not logged into any GitHub hosts. To log in, run: gh auth login"))
    }

    func testAuthFailureReasonSeparatesATimeoutFromSignedOut() {
        XCTAssertEqual(GitHubJSON.authFailureReason("You are not logged into any GitHub hosts."), "not signed in to GitHub")
        XCTAssertEqual(GitHubJSON.authFailureReason("X Timeout trying to log in to github.com account octo (keyring)"), "gh could not reach github.com")
    }
}
