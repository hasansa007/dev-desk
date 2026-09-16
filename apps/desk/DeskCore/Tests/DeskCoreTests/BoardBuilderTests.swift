import XCTest
@testable import DeskCore

/// The remedy an unavailable GitHub carries, pinned here so a change to the wording has to be deliberate.
private let install = "Install the GitHub CLI (`brew install gh`), then `gh auth login`."

final class BoardBuilderTests: XCTestCase {
    private static let issue12Body = """
    ## Summary

    - context bullet
    > quote

    The app crashes when the config file is missing.
    It should fall back to defaults.

    - [x] Launch without a config file
    - [ ] Log a warning

    Blocked by #14 and blocks #15. Depends on #16.
    """.replacingOccurrences(of: "\n", with: "\r\n")

    private static let bootDiff = FileDiff(path: "Sources/App/Launch/Boot.swift", hunks: [
        DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [DiffLine(.deletion, "load()"), DiffLine(.addition, "load(fallback: .defaults)")]),
    ])

    private static let mergedReason = "Merged on 2026-09-10. Dev Desk reads only open work; open the pull request for its description, commits, diff and checks."

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func issue(_ number: Int, _ title: String, labels: [String] = [], milestone: String? = nil,
                       updatedAt: String = "2026-09-01T00:00:00Z", body: String = "") -> GitHubIssue {
        GitHubIssue(number: number, title: title, labels: labels.map { GitHubLabel(name: $0) },
                    milestone: milestone.map { GitHubIssue.MilestoneRef(title: $0) }, updatedAt: updatedAt, body: body,
                    url: "https://github.com/acme/app/issues/\(number)")
    }

    private func pr(_ number: Int, _ title: String, head: String, decision: String = "", draft: Bool = false, fork: Bool = false,
                    body: String = "") -> GitHubPullRequest {
        GitHubPullRequest(number: number, title: title, headRefName: head, isCrossRepository: fork, reviewDecision: decision, isDraft: draft,
                          url: "https://github.com/acme/app/pull/\(number)", body: body)
    }

    private var fixture: BoardInput {
        let git = GitFacts(base: "main", baseRef: "main", baseShort: "abc1234", branches: [
            BranchFacts(name: "gh-12-x", unmerged: 2, counted: true, worktree: "/tmp/wt/app-12",
                        commits: [GitCommit(sha: "c0ffee1", author: "Ada", date: "2026-09-11T09:30:00Z", subject: "Guard *nil* [config]"),
                                  GitCommit(sha: "beef002", author: "Bob", date: "2026-09-03T18:00:00Z", subject: "Add test")],
                        files: [NumstatEntry(path: "Sources/App/Launch/Boot.swift", additions: 10, deletions: 2),
                                NumstatEntry(path: "Assets/icon.png", additions: nil, deletions: nil)],
                        diffs: ["Sources/App/Launch/Boot.swift": Self.bootDiff]),
            BranchFacts(name: "gh-13-y", unmerged: 1, counted: true, worktree: nil,
                        commits: [GitCommit(sha: "d00d003", author: "Cy", date: "2026-09-10T10:00:00Z", subject: "Batch sync")]),
            BranchFacts(name: "old/stale", unmerged: 0, counted: true, worktree: nil),
            BranchFacts(name: "spike/z", unmerged: 1, counted: true, worktree: nil,
                        commits: [GitCommit(sha: "e1e1e14", author: "Di", date: "2026-09-11T08:00:00Z", subject: "Try it")]),
        ])
        let github = GitHubData(
            slug: "acme/app", account: "octo",
            issues: [
                issue(12, "Crash on launch", body: Self.issue12Body),
                issue(13, "Slow sync"),
                issue(14, "Export to CSV", milestone: "v2"),
                issue(15, "Dark mode", updatedAt: "2026-08-01T00:00:00Z"),
                issue(16, "Leftover polish", labels: ["epic-leftover"]),
                issue(17, "Epic: offline", labels: ["epic"], body: "- [x] #12\n- [ ] #18"),
                issue(18, "Offline cache", labels: ["P1"], updatedAt: "2026-09-05T00:00:00Z"),
                issue(19, "Retry uploads"),
            ],
            openPullRequests: [
                pr(20, "Refactor networking", head: "refactor/net", decision: "REVIEW_REQUIRED", body: "Moves the client.\n\n- [ ] Tests pass"),
                pr(30, "Batch the sync", head: "gh-13-y", decision: "CHANGES_REQUESTED"),
                pr(31, "Retry with backoff", head: "feature/retry", body: "Fixes #19"),
            ],
            mergedPullRequests: [GitHubMergedPullRequest(number: 9, title: "Ship onboarding", headRefName: "feat/onboarding",
                                                         mergedAt: "2026-09-10T08:00:00Z", url: "https://github.com/acme/app/pull/9")],
            milestones: [GitHubMilestone(title: "v2", dueOn: "2026-10-01T07:00:00Z")],
            checks: [30: .read([GitHubCheck(name: "unit", bucket: "pass"), GitHubCheck(name: "lint", bucket: "fail"),
                                GitHubCheck(name: "e2e", bucket: "pending"), GitHubCheck(name: "deploy", bucket: "skipping"),
                                GitHubCheck(name: "docs", bucket: "cancel")]),
                     20: .read([])])
        return BoardInput(git: git, github: github, activeMilestone: "v2",
                          pipeline: ["gh-12-x": PipelineState(phase: 9, phaseGroup: "coding", tier: "standard")],
                          now: date("2026-09-11T12:00:00Z"), timeZone: TimeZone(identifier: "UTC")!)
    }

    private func tasks(_ input: BoardInput? = nil) -> [String: DeskTask] {
        Dictionary(BoardBuilder.build(input ?? fixture).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func testEveryRuleLandsInItsColumnAndNothingElseAppears() {
        let built = BoardBuilder.build(fixture)
        let columns = Dictionary(built.map { ($0.id, $0.column) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(built.count, columns.count, "task ids are unique")
        XCTAssertEqual(columns, [
            "12": .inProgress, "13": .review, "14": .readyForDev, "15": .backlog, "16": .backlog, "18": .backlog, "19": .review,
            "pr:20": .review, "branch:spike/z": .inProgress, "merged:9": .done,
        ])
    }

    func testIssueWithBranchAheadIsInProgressWithItsWorktree() throws {
        let task = try XCTUnwrap(tasks()["12"])
        XCTAssertEqual(task.issueNumber, 12)
        XCTAssertEqual(task.title, "Crash on launch")
        // The count is a field on every card now; the pill kept only the dialog's header, where nothing repeats it.
        XCTAssertNil(task.cardBadge)
        XCTAssertEqual(task.headerBadge, StatusBadge(.neutral, "2 commits ahead"))
        XCTAssertEqual(task.unmergedCount, 2)
        XCTAssertEqual(task.nextAction, .reviewChanges)
        XCTAssertEqual(task.branchLine, "gh-12-x · base main@abc1234 · worktree /tmp/wt/app-12")
        XCTAssertEqual(task.parallelLine, "gh-12-x · /tmp/wt/app-12")
    }

    func testChangesRequestedPullRequestPutsItsIssueInReview() throws {
        let task = try XCTUnwrap(tasks()["13"])
        XCTAssertEqual(task.cardBadge, StatusBadge(.failed, "Changes requested"))
        XCTAssertEqual(task.headerBadge, StatusBadge(.failed, "Changes requested"))
        XCTAssertEqual(task.nextAction, .reviewChanges)
        XCTAssertEqual(task.branchLine, "gh-13-y · base main@abc1234")
        XCTAssertEqual(task.pullRequestNumber, 30, "the Review card's backwards move needs the PR number")
    }

    /// The active milestone means "ready for dev" now (ADR 0035): Queued is the wait for a free agent slot.
    func testActiveMilestoneIssueIsReadyForDevWithNoBranch() throws {
        let task = try XCTUnwrap(tasks()["14"])
        XCTAssertNil(task.cardBadge)
        XCTAssertEqual(task.headerBadge, StatusBadge(.neutral, "Ready for dev"))
        XCTAssertEqual(task.branchLine, "No branch yet")
        XCTAssertEqual(task.nextAction, .openURL(URL(string: "https://github.com/acme/app/issues/14")!, title: "Open on GitHub"))
        XCTAssertEqual(task.activity, .available([]))
        XCTAssertEqual(task.changes, .available(ChangeSet(files: [], baseNote: "No branch yet.")))
        XCTAssertEqual(task.parallel, .none("No branch yet"))
    }

    func testRatingLabelsAreReadFromTheIssueAndAnUnratedOneStaysNil() {
        let input = BoardInput(git: nil, github: GitHubData(slug: "acme/app", issues: [
            issue(30, "Rated", labels: ["impact:high", "complexity:Low"]),
            issue(31, "Unrated", labels: ["enhancement"]),
        ]))
        let tasks = BoardBuilder.build(input)
        XCTAssertEqual(tasks.first { $0.id == "30" }?.impact, "High")
        XCTAssertEqual(tasks.first { $0.id == "30" }?.complexity, "Low")
        XCTAssertNil(tasks.first { $0.id == "31" }?.impact)
        XCTAssertNil(tasks.first { $0.id == "31" }?.complexity)
    }

    func testARatingLabelWithNoValueIsNotARating() {
        XCTAssertNil(DeskTask.rating("impact", in: ["impact:"]))
        XCTAssertNil(DeskTask.rating("impact", in: ["impactful"]))
        XCTAssertEqual(DeskTask.rating("complexity", in: ["Complexity:MEDIUM"]), "Medium")
    }

    func testBacklogAndDeferredBadges() throws {
        let plain = try XCTUnwrap(tasks()["15"])
        XCTAssertNil(plain.cardBadge)
        XCTAssertEqual(plain.headerBadge, StatusBadge(.neutral, "Backlog"))
        let deferred = try XCTUnwrap(tasks()["16"])
        XCTAssertEqual(deferred.cardBadge, StatusBadge(.neutral, "Deferred"))
        XCTAssertEqual(deferred.headerBadge, StatusBadge(.neutral, "Deferred"))
    }

    func testBacklogOrderPutsP1BeforeAnOlderUnlabelledIssueThenDeferred() {
        let backlog = BoardBuilder.build(fixture).filter { $0.column == .backlog }.map(\.id)
        XCTAssertEqual(backlog, ["18", "15", "16"])
    }

    func testSliceNumberOrdersWithinAPriority() {
        var input = fixture
        input.github?.issues = [issue(40, "Import slice 2", labels: ["P2"], updatedAt: "2026-01-01T00:00:00Z"),
                                issue(41, "Import slice 1", labels: ["P2"], updatedAt: "2026-06-01T00:00:00Z")]
        XCTAssertEqual(BoardBuilder.build(input).filter { $0.column == .backlog }.map(\.id), ["41", "40"])
    }

    func testEpicWithOpenChildIsOnlyHiddenFromTheBacklog() {
        var input = fixture
        input.github?.issues = [issue(17, "Epic: offline", labels: ["epic"], milestone: "v2", body: "- [ ] #18"),
                                issue(21, "Epic: done", labels: ["epic"], body: "- [x] #12")]
        let columns = BoardBuilder.build(input).reduce(into: [String: BoardColumn]()) { $0[$1.id] = $1.column }
        XCTAssertEqual(columns["17"], .readyForDev)
        XCTAssertEqual(columns["21"], .backlog)
    }

    func testClosingKeywordLinksAPullRequestWhoseBranchIsNotLocal() throws {
        let task = try XCTUnwrap(tasks()["19"])
        XCTAssertEqual(task.cardBadge, StatusBadge(.info, "PR open"))
        XCTAssertEqual(task.branchLine, "feature/retry · base main@abc1234")
        XCTAssertEqual(task.nextAction, .openURL(URL(string: "https://github.com/acme/app/pull/31")!, title: "Open pull request"))
        XCTAssertEqual(task.changes, .unavailable("The branch feature/retry is not in this checkout. Fetch it to see its diff."))
        XCTAssertEqual(task.activity, .unavailable("The branch feature/retry is not in this checkout. Fetch it to see its commits."))
    }

    func testMissingBranchNameIsEscapedNotPlacedInACodeSpan() throws {
        let head = "feat/`[x](file:///Applications/Calculator.app)"
        let input = BoardInput(git: GitFacts(base: "main", baseRef: "refs/heads/main", baseShort: "abc1234", branches: []),
                               github: GitHubData(slug: "acme/app", openPullRequests: [pr(7, "Spiky", head: head)]),
                               activeMilestone: nil, now: date("2026-09-11T12:00:00Z"), timeZone: TimeZone(identifier: "UTC")!)
        let task = try XCTUnwrap(tasks(input)["pr:7"])
        let changes = try XCTUnwrap(task.changes.unavailableReason)
        let activity = try XCTUnwrap(task.activity.unavailableReason)
        for reason in [changes, activity] {
            XCTAssertFalse(reason.contains("[x]("), "a raw link would render as a one-click launch")
            XCTAssertFalse(reason.contains("The branch `"), "the branch name must not open a code span")
            XCTAssertTrue(reason.contains("feat/\\`\\[x\\]"), "the branch name is escaped literally")
        }
    }

    func testUnlinkedPullRequestBecomesItsOwnReviewTask() throws {
        let task = try XCTUnwrap(tasks()["pr:20"])
        XCTAssertNil(task.issueNumber)
        XCTAssertEqual(task.title, "Refactor networking")
        XCTAssertEqual(task.cardMeta, "PR #20")
        XCTAssertEqual(task.cardBadge, StatusBadge(.info, "Review requested"))
        XCTAssertEqual(task.pullRequestNumber, 20)
        XCTAssertEqual(task.requirements, .available(Requirements(goal: "Moves the client.", criteria: [AcceptanceCriterion("Tests pass", isMet: false)],
                                                                  sources: "Pull request #20", body: "Moves the client.\n\n- [ ] Tests pass")))
        XCTAssertEqual(task.changes, .unavailable("The branch refactor/net is not in this checkout. Fetch it to see its diff."))
    }

    func testBranchWithoutAnIssueIsInProgress() throws {
        let task = try XCTUnwrap(tasks()["branch:spike/z"])
        XCTAssertNil(task.issueNumber)
        XCTAssertEqual(task.title, "spike/z")
        // The count is a field every card carries now, so the pill that said it a second time is gone; the
        // dialog's header still shows it, because nothing else there says how far ahead the branch is.
        XCTAssertNil(task.cardBadge)
        XCTAssertEqual(task.headerBadge, StatusBadge(.neutral, "1 commit ahead"))
        XCTAssertEqual(task.unmergedCount, 1)
        XCTAssertEqual(task.nextAction, .reviewChanges)
        XCTAssertEqual(task.requirements, .unavailable("No linked issue. Name the branch gh-<number>-… to link one."))
        XCTAssertEqual(task.dependencies, [])
    }

    func testMergedPullRequestIsDimmedDone() throws {
        let task = try XCTUnwrap(tasks()["merged:9"])
        XCTAssertEqual(task.issueNumber, 9)
        XCTAssertEqual(task.title, "Ship onboarding")
        XCTAssertEqual(task.cardMeta, "merged")
        XCTAssertTrue(task.isDimmed)
        XCTAssertNil(task.cardBadge)
        XCTAssertEqual(task.headerBadge, StatusBadge(.ended, "Merged"))
        XCTAssertEqual(task.branchLine, "feat/onboarding · merged 2026-09-10")
        XCTAssertEqual(task.nextAction, .openURL(URL(string: "https://github.com/acme/app/pull/9")!, title: "Open pull request"))
        XCTAssertEqual(task.requirements, .unavailable(Self.mergedReason))
        XCTAssertEqual(task.changes, .unavailable(Self.mergedReason))
        XCTAssertEqual(task.activity, .unavailable(Self.mergedReason))
        XCTAssertEqual(task.evidence, .unavailable(Self.mergedReason))
    }

    func testReviewBadgesPreferDraftThenFollowTheDecision() {
        let prs = [pr(1, "a", head: "a", decision: "APPROVED", draft: true), pr(2, "b", head: "b", decision: "CHANGES_REQUESTED"),
                   pr(3, "c", head: "c", decision: "APPROVED"), pr(4, "d", head: "d", decision: "REVIEW_REQUIRED"), pr(5, "e", head: "e")]
        let input = BoardInput(git: nil, github: GitHubData(slug: "acme/app", openPullRequests: prs), activeMilestone: nil,
                               now: date("2026-09-11T12:00:00Z"), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(BoardBuilder.build(input).map(\.cardBadge), [
            StatusBadge(.neutral, "Draft"), StatusBadge(.failed, "Changes requested"), StatusBadge(.running, "Approved"),
            StatusBadge(.info, "Review requested"), StatusBadge(.info, "PR open"),
        ])
    }

    func testCommitsBecomeActivityWithTodayTimesAndEscapedMarkdown() throws {
        let task = try XCTUnwrap(tasks()["12"])
        let events = [
            ActivityEvent(id: "c0ffee1", time: "09:30", text: "**Ada** Guard \\*nil\\* \\[config\\]",
                          detail: ToolDetail(title: "Commit c0ffee1", lines: ["2026-09-11T09:30:00Z"])),
            ActivityEvent(id: "beef002", time: "3 Sep", text: "**Bob** Add test",
                          detail: ToolDetail(title: "Commit beef002", lines: ["2026-09-03T18:00:00Z"])),
        ]
        XCTAssertEqual(task.activity, .available(events))
        XCTAssertEqual(task.parallel, .activity(events))
    }

    func testRequirementsTakeTheFirstProseParagraphAndTheChecklist() throws {
        let task = try XCTUnwrap(tasks()["12"])
        XCTAssertEqual(task.requirements, .available(Requirements(
            goal: "The app crashes when the config file is missing. It should fall back to defaults.",
            criteria: [AcceptanceCriterion("Launch without a config file", isMet: true), AcceptanceCriterion("Log a warning", isMet: false)],
            sources: "Issue #12", body: Self.issue12Body)))
        XCTAssertEqual(tasks()["13"]?.requirements.value?.goal, "Slow sync")
    }

    func testDependenciesComeFromTheBody() throws {
        XCTAssertEqual(try XCTUnwrap(tasks()["12"]).dependencies, [
            Dependency(text: "Blocked by [#14](desk://task/14)", taskID: "14"),
            Dependency(text: "Blocked by [#16](desk://task/16)", taskID: "16"),
            Dependency(text: "Blocks [#15](desk://task/15)", taskID: "15"),
        ])
    }

    func testChangesComeFromTheDiffWithTwoComponentPaths() throws {
        XCTAssertEqual(try XCTUnwrap(tasks()["12"]).changes, .available(ChangeSet(
            files: [ChangedFile(id: "Sources/App/Launch/Boot.swift", displayPath: "Launch/Boot.swift", additions: 10, deletions: 2),
                    ChangedFile(id: "Assets/icon.png", displayPath: "Assets/icon.png", additions: nil, deletions: nil)],
            baseNote: "Diff is against main at `abc1234`.",
            diffs: ["Sources/App/Launch/Boot.swift": Self.bootDiff])))
    }

    func testBaseBranchNameIsEscapedNotPlacedInACodeSpan() throws {
        let base = "wip/`[x](file:///Applications/Calculator.app)"
        let input = BoardInput(git: GitFacts(base: base, baseRef: "refs/heads/\(base)", baseShort: "abc1234",
                                             branches: [BranchFacts(name: "spike", unmerged: 1, counted: true, worktree: nil)]),
                               github: nil, activeMilestone: nil, now: date("2026-09-11T12:00:00Z"), timeZone: TimeZone(identifier: "UTC")!)
        let note = try XCTUnwrap(tasks(input)["branch:spike"]?.changes.value?.baseNote)
        XCTAssertEqual(note, "Diff is against wip/\\`\\[x\\](file\\:///Applications/Calculator.app) at `abc1234`.")
        XCTAssertFalse(note.contains("[x]("), "a raw link would render as a one-click launch")
        XCTAssertFalse(note.hasPrefix("Diff is against `"), "the base name must not open a code span")
    }

    func testPipelineStateAddsACardNoteStagesAndAnAdvisoryCheck() throws {
        let task = try XCTUnwrap(tasks()["12"])
        XCTAssertEqual(task.cardNote, "Phase 9 · coding · advisory")
        XCTAssertEqual(task.pipeline, PipelineState(phase: 9).progress)
        XCTAssertEqual(task.evidence, .available(Evidence(isDemo: false, checks: [
            CheckResult(id: "pipeline", name: "Pipeline state", outcome: .passed, outcomeLabel: "phase 9 · standard", revisionLabel: "advisory"),
        ])))
        let unstaged = try XCTUnwrap(tasks()["13"])
        XCTAssertNil(unstaged.cardNote)
        XCTAssertNil(unstaged.pipeline)
    }

    func testPullRequestChecksMapBucketsAndCarryTheLimitation() throws {
        let evidence = try XCTUnwrap(tasks()["13"]?.evidence.value)
        XCTAssertFalse(evidence.isDemo)
        XCTAssertEqual(evidence.checks.map(\.outcome), [.passed, .failed, .warning, .warning, .warning])
        XCTAssertEqual(evidence.checks.map(\.outcomeLabel), ["passed", "failed", "pending", "skipping", "cancel"])
        XCTAssertEqual(Set(evidence.checks.map(\.revisionLabel)), ["PR #30"])
        XCTAssertEqual(evidence.limitations, "CI results reported by GitHub for this pull request. Dev Desk has not verified behaviour in a running app.")
        XCTAssertNil(tasks()["14"]?.evidence.value?.limitations)
    }

    func testABranchStillAtItsMergedPullRequestsHeadIsOnlyDone() {
        var input = fixture
        input.git?.branches.append(BranchFacts(name: "feat/onboarding", unmerged: 3, counted: true, worktree: nil, head: Self.mergedHead))
        input.github?.mergedPullRequests[0].headRefOid = Self.mergedHead
        let built = tasks(input)
        XCTAssertNil(built["branch:feat/onboarding"], "a squash merge leaves the branch's own commits outside the base")
        XCTAssertNotNil(built["merged:9"])
    }

    func testABranchWithCommitsAfterItsMergeStaysInProgress() {
        var input = fixture
        input.git?.branches.append(BranchFacts(name: "feat/onboarding", unmerged: 3, counted: true, worktree: nil,
                                               head: "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a"))
        input.github?.mergedPullRequests[0].headRefOid = Self.mergedHead
        XCTAssertEqual(tasks(input)["branch:feat/onboarding"]?.column, .inProgress)
    }

    private static let mergedHead = "9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f9f"

    func testEveryLocalTaskCarriesTheBaseRefItsAgentWorktreeStartsFrom() {
        var input = fixture
        input.git?.baseRef = "refs/remotes/origin/main"
        for task in BoardBuilder.build(input) {
            XCTAssertEqual(task.baseRef, "refs/remotes/origin/main", task.id)
        }
        input.git = nil
        let withoutGit = BoardBuilder.build(input)
        XCTAssertFalse(withoutGit.isEmpty)
        for task in withoutGit {
            XCTAssertNil(task.baseRef, task.id)
        }
    }

    func testEveryTaskCarriesItsBranchWhenOneIsKnown() throws {
        let built = tasks()
        XCTAssertEqual(try XCTUnwrap(built["12"]).branch, "gh-12-x", "an issue with a matched local branch")
        XCTAssertEqual(try XCTUnwrap(built["13"]).branch, "gh-13-y")
        XCTAssertEqual(try XCTUnwrap(built["19"]).branch, "feature/retry", "a linked pull request's head, even when it isn't local")
        XCTAssertEqual(try XCTUnwrap(built["pr:20"]).branch, "refactor/net")
        XCTAssertEqual(try XCTUnwrap(built["branch:spike/z"]).branch, "spike/z", "a branch-only task")
        XCTAssertEqual(try XCTUnwrap(built["merged:9"]).branch, "feat/onboarding")
        XCTAssertNil(try XCTUnwrap(built["14"]).branch, "no branch yet")
        XCTAssertNil(try XCTUnwrap(built["15"]).branch)
        XCTAssertEqual(built.values.compactMap(\.noBranchNote), [], "no pull request here comes from a fork")
    }

    func testABranchOnlyTaskTakesItsNumberFromAGhPrefix() throws {
        var input = fixture
        input.github = nil
        input.activeMilestone = nil
        let task = try XCTUnwrap(tasks(input)["branch:gh-12-x"])
        XCTAssertNil(task.issueNumber)
        XCTAssertEqual(task.branch, "gh-12-x")
        XCTAssertEqual(task.taskNumber, 12)
    }

    func testAForkHeadIsNeverTakenForABranchHere() throws {
        let fork = "This pull request comes from a fork, so its branch isn't in this repository. The shell opens at the project root."
        let git = GitFacts(base: "main", baseRef: "refs/heads/main", baseShort: "abc1234",
                           branches: [BranchFacts(name: "gh-50-mine", unmerged: 1, counted: true, worktree: nil)])
        let github = GitHubData(slug: "acme/app", issues: [issue(51, "Linked to a fork")], openPullRequests: [
            pr(60, "From someone's main", head: "main", fork: true),
            // Its head has the name of a local branch of ours, which is not the fork's branch.
            pr(61, "A fork's fix", head: "gh-50-mine", fork: true, body: "Fixes #51"),
            pr(62, "From this repository", head: "feature/same"),
        ], mergedPullRequests: [GitHubMergedPullRequest(number: 63, title: "Merged from a fork", headRefName: "main", isCrossRepository: true,
                                                        mergedAt: "2026-09-10T08:00:00Z", url: "https://github.com/acme/app/pull/63")])
        let built = tasks(BoardInput(git: git, github: github, activeMilestone: nil,
                                     now: date("2026-09-11T12:00:00Z"), timeZone: TimeZone(identifier: "UTC")!))
        for id in ["pr:60", "51", "merged:63"] {
            let task = try XCTUnwrap(built[id], id)
            XCTAssertNil(task.branch, id)
            XCTAssertEqual(task.noBranchNote, fork, id)
        }
        let same = try XCTUnwrap(built["pr:62"])
        XCTAssertEqual(same.branch, "feature/same")
        XCTAssertNil(same.noBranchNote)
    }

    func testTaskNumberIsTheIssueElseAGhPrefixOnTheBranch() {
        func task(_ issue: Int?, _ branch: String?) -> DeskTask {
            DeskTask(id: "t", issueNumber: issue, title: "t", column: .inProgress, headerBadge: StatusBadge(.neutral, "t"), branchLine: "",
                     branch: branch, requirements: .unavailable(""), changes: .unavailable(""), evidence: .unavailable(""), parallel: .none(""))
        }
        XCTAssertEqual(task(12, "gh-99-x").taskNumber, 12)
        XCTAssertEqual(task(nil, "gh-7-demo").taskNumber, 7)
        XCTAssertNil(task(nil, "gh-7").taskNumber, "the prefix ends with a dash")
        XCTAssertNil(task(nil, "7-demo").taskNumber)
        XCTAssertNil(task(nil, "feature/gh-7-x").taskNumber)
        XCTAssertNil(task(nil, "gh--x").taskNumber)
        XCTAssertNil(task(nil, nil).taskNumber)
    }

    func testWithoutGitHubOnlyLocalBranchesShow() {
        var input = fixture
        input.github = nil
        input.activeMilestone = nil
        let built = BoardBuilder.build(input)
        XCTAssertEqual(built.map(\.id), ["branch:gh-12-x", "branch:gh-13-y", "branch:spike/z"])
        XCTAssertTrue(built.allSatisfy { $0.column == .inProgress && $0.requirements.unavailableReason != nil })
    }

    func testBoardNoteNamesTheRuleAndTheActiveMilestone() {
        let ready = GitHubState.ready(GitHubData(slug: "acme/app"))
        let rule = "Git decides In progress, Review and Done; the active milestone puts an issue in Ready for dev. "
            + "Ready for dev, Queued and a started card's In progress are recorded in .devdesk/board.json until git sees a commit."
        XCTAssertEqual(BoardBuilder.note(github: ready, activeMilestone: ("v2", "nearest due date 2026-10-01")),
                       rule + " Active milestone: v2, nearest due date 2026-10-01.")
        XCTAssertEqual(BoardBuilder.note(github: ready, activeMilestone: (nil, "no open milestone")),
                       rule + " No active milestone, so only moves made here fill Ready for dev.")
        // An unavailable GitHub says what to do about it: the note is the only place the developer is told.
        XCTAssertEqual(BoardBuilder.note(github: .unavailable("gh not installed"), activeMilestone: (nil, "gh not installed")),
                       "GitHub is unavailable (gh not installed), so the board shows local branches and docs/backlog/. " + install)
        var noIssues = GitHubData(slug: "acme/app")
        noIssues.issuesUnavailable = "the 'acme/app' repository has disabled issues"
        XCTAssertEqual(BoardBuilder.note(github: .ready(noIssues), activeMilestone: (nil, "no open milestone")),
                       rule + " No active milestone, so only moves made here fill Ready for dev. Open issues could not be read "
                       + "(the 'acme/app' repository has disabled issues), so only pull requests and branches are shown.")
    }

    func testUnreadAndFailedChecksAreUnavailableRatherThanEmpty() throws {
        XCTAssertEqual(tasks()["19"]?.evidence, .unavailable("Checks are read for the 10 newest open pull requests; this one was not read."))
        XCTAssertEqual(tasks()["pr:20"]?.evidence, .available(Evidence(isDemo: false)))
        var input = fixture
        input.github?.checks[30] = .failed("HTTP 502: Bad Gateway")
        XCTAssertEqual(tasks(input)["13"]?.evidence, .unavailable("gh pr checks failed: HTTP 502: Bad Gateway"))
    }

    func testFailedGitReadsAreUnavailableWithTheirReasonWhileTheCountStays() throws {
        var input = fixture
        input.git?.branches[0].logFailure = "fatal: bad object c0ffee1"
        input.git?.branches[0].diffFailure = "git did not finish within 15 seconds"
        let task = try XCTUnwrap(tasks(input)["12"])
        XCTAssertEqual(task.headerBadge, StatusBadge(.neutral, "2 commits ahead"))
        XCTAssertEqual(task.unmergedCount, 2, "a failed diff read must not lose the count the card is named for")
        XCTAssertEqual(task.activity, .unavailable("git log failed: fatal: bad object c0ffee1"))
        XCTAssertEqual(task.changes, .unavailable("git diff failed: git did not finish within 15 seconds"))
        XCTAssertEqual(task.parallel, .none("git log failed: fatal: bad object c0ffee1"))
    }

    // MARK: - Stored stages (ADR 0035)

    /// The stage fills the gap before the first commit: an issue git has nothing on lands where the file says.
    func testAStoredStagePutsAnUntouchedIssueInItsColumn() {
        var input = fixture
        input.stages = ["15": .readyForDev, "18": .queued]
        let built = tasks(input)
        XCTAssertEqual(built["15"]?.column, .readyForDev)
        XCTAssertEqual(built["18"]?.column, .queued)
        XCTAssertEqual(built["18"]?.headerBadge, StatusBadge(.neutral, "Queued"), "the fallback badge names its column")
    }

    /// A start records In progress before git has a commit to show for it (ADR 0035).
    func testAStoredInProgressStageMovesAnIssueWithNoBranch() {
        var input = fixture
        input.stages = ["15": .inProgress]
        XCTAssertEqual(tasks(input)["15"]?.column, .inProgress)
    }

    /// A queued card says why it is waiting; a pipeline note of the card's own still wins — it describes
    /// the work, which says more than the wait.
    func testAQueuedCardCarriesTheWaitingNoteUnlessThePipelineSpeaks() {
        var input = fixture
        input.stages = ["15": .queued, "18": .queued, "local:c1-idle": .queued]
        // Issue 18's branch has nothing unmerged, so git declines and the stage holds — and the branch's
        // pipeline state gives the card a note of its own.
        input.git?.branches.append(BranchFacts(name: "gh-18-cache", unmerged: 0, counted: true, worktree: nil))
        input.pipeline["gh-18-cache"] = PipelineState(phase: 5, phaseGroup: "planning", tier: "standard")
        input.localBacklog = [BacklogItem(id: "c1-idle", key: "C1", title: "Waiting locally", body: "", path: "/p/docs/backlog/c1-idle.md")]
        let built = tasks(input)
        XCTAssertEqual(built["15"]?.column, .queued)
        XCTAssertEqual(built["15"]?.cardNote, "Waiting for a free agent slot")
        XCTAssertEqual(built["local:c1-idle"]?.cardNote, "Waiting for a free agent slot", "a docs/backlog/ card waits the same way")
        XCTAssertEqual(built["18"]?.column, .queued)
        XCTAssertEqual(built["18"]?.cardNote, "Phase 5 · planning · advisory", "the pipeline's note wins")
    }

    /// git wins once commits exist: clearing or downgrading the stage cannot pull a branch's card back.
    func testUnmergedCommitsBeatAStoredReadyForDevStage() {
        var input = fixture
        input.stages = ["12": .readyForDev]
        XCTAssertEqual(tasks(input)["12"]?.column, .inProgress, "gh-12-x is 2 commits ahead; git decides In progress")
    }

    /// And so does an open pull request — Review is git's column, whatever the file says.
    func testAnOpenPullRequestBeatsAStoredStage() {
        var input = fixture
        input.stages = ["13": .readyForDev]
        XCTAssertEqual(tasks(input)["13"]?.column, .review)
    }

    /// A stage under a `branch:`/`pr:`/`merged:` id is stale bookkeeping about a card git owns, never a move.
    func testAStageUnderAGitOwnedIdIsIgnored() {
        var input = fixture
        input.stages = ["branch:spike/z": .readyForDev, "pr:20": .queued, "merged:9": .readyForDev]
        let built = tasks(input)
        XCTAssertEqual(built["branch:spike/z"]?.column, .inProgress)
        XCTAssertEqual(built["pr:20"]?.column, .review)
        XCTAssertEqual(built["merged:9"]?.column, .done)
    }

    /// A draft pull request is still being worked on, so it sits with the work — which is what makes the
    /// Review card's "convert to a draft" a real move back to In progress.
    func testADraftPullRequestIsInProgressNotReview() {
        var input = fixture
        input.github?.openPullRequests = [pr(30, "Batch the sync", head: "gh-13-y", decision: "CHANGES_REQUESTED", draft: true),
                                          pr(40, "Standalone draft", head: "wip/x", draft: true),
                                          pr(41, "Ready for eyes", head: "feat/ready")]
        let built = tasks(input)
        XCTAssertEqual(built["13"]?.column, .inProgress, "an issue whose pull request is a draft")
        XCTAssertEqual(built["pr:40"]?.column, .inProgress, "a draft with no issue behind it")
        XCTAssertEqual(built["pr:41"]?.column, .review, "a non-draft pull request stays in Review")
    }

    /// Work recorded with no tracker is on the board, in Backlog, marked as local (ADR 0027).
    func testALocalBacklogEntryIsABacklogCard() {
        let item = BacklogItem(id: "c1-callback", key: "C1", title: "Callback fetch returns 0", area: "Logic",
                               impact: "High", body: "mechanism: it schedules and returns.", path: "/p/docs/backlog/c1-callback.md")
        let tasks = BoardBuilder.build(BoardInput(localBacklog: [item]))
        let card = tasks.first { $0.isLocalBacklog }
        XCTAssertEqual(card?.id, "local:c1-callback")
        XCTAssertEqual(card?.localBacklogID, "c1-callback")
        XCTAssertEqual(card?.column, .backlog)
        XCTAssertNil(card?.issueNumber, "nothing has been filed to a tracker")
        XCTAssertEqual(card?.cardBadge?.label, "Local")
        XCTAssertEqual(card?.impact, "High")
        XCTAssertEqual(card?.requirements.value?.body, "mechanism: it schedules and returns.")
    }

    /// A `docs/backlog/` card carries a stage like any issue card, and keeps its Local badges (ADR 0035).
    func testALocalBacklogEntryCarriesItsStoredStage() {
        let item = BacklogItem(id: "c1-callback", key: "C1", title: "Callback fetch returns 0", area: "Logic",
                               impact: "High", body: "mechanism: it schedules and returns.", path: "/p/docs/backlog/c1-callback.md")
        let card = BoardBuilder.build(BoardInput(localBacklog: [item], stages: ["local:c1-callback": .readyForDev]))
            .first { $0.isLocalBacklog }
        XCTAssertEqual(card?.column, .readyForDev)
        XCTAssertEqual(card?.cardBadge?.label, "Local")
        XCTAssertEqual(card?.headerBadge, StatusBadge(.info, "Local backlog"))
    }

    /// Finished local work reaches Done. Git owns Done for an issue card (a merged pull request), and for a
    /// local card that rule can never fire — no branch, no pull request — so the card's own file says it.
    func testALocalBacklogEntryMarkedDoneIsADoneCard() {
        let item = BacklogItem(id: "c1-callback", key: "C1", title: "Callback fetch returns 0", area: "Logic",
                               status: "done", resolved: "2026-09-15 · 99564f1", body: "",
                               path: "/p/docs/backlog/c1-callback.md")
        let card = BoardBuilder.build(BoardInput(localBacklog: [item])).first { $0.isLocalBacklog }
        XCTAssertEqual(card?.column, .done)
        XCTAssertEqual(card?.branchLine, "Done · 2026-09-15 · 99564f1", "there is no branch, so the line carries what closed it")
        XCTAssertFalse(card?.isMerged ?? true, "done is not merged: nothing was ever pushed")
    }

    /// The case this was written for: a run that was interrupted left `inProgress` in board.json, and the
    /// work got finished anyway. The file outranks the leftover stage, or the card is stuck forever.
    func testACardMarkedDoneBeatsALeftoverInProgressStage() {
        let item = BacklogItem(id: "c1-callback", key: "C1", title: "Callback fetch returns 0",
                               status: "done", body: "", path: "/p/docs/backlog/c1-callback.md")
        let card = BoardBuilder.build(BoardInput(localBacklog: [item], stages: ["local:c1-callback": .inProgress]))
            .first { $0.isLocalBacklog }
        XCTAssertEqual(card?.column, .done)
    }

    /// `status:` is read case-insensitively, and anything that is not done changes nothing.
    func testOnlyDoneMovesTheCardAndTheSpellingDoesNotMatter() {
        func column(_ status: String?) -> BoardColumn? {
            let item = BacklogItem(id: "c1", key: "C1", title: "t", status: status, body: "", path: "/p/docs/backlog/c1.md")
            return BoardBuilder.build(BoardInput(localBacklog: [item])).first { $0.isLocalBacklog }?.column
        }
        XCTAssertEqual(column("done"), .done)
        XCTAssertEqual(column(nil), .backlog)
        XCTAssertEqual(column("blocked"), .backlog, "an unknown status is not a column")
        // The parser lowercases what it reads, which is where a hand-typed `Done` is normalised.
        XCTAssertEqual(LocalBacklog.parse("---\nkey: C1\ntitle: t\nstatus: Done\n---\n", id: "c1", path: "/p").status, "done")
    }

    /// A done card records no commit when the card does not name one — and says so rather than inventing one.
    func testADoneCardWithNoResolvedLineSaysSo() {
        let item = BacklogItem(id: "c1", key: "C1", title: "t", status: "done", body: "", path: "/p/docs/backlog/c1.md")
        let card = BoardBuilder.build(BoardInput(localBacklog: [item])).first { $0.isLocalBacklog }
        XCTAssertEqual(card?.branchLine, "Done — the card records no commit")
    }

    /// An entry that already names its issue is on its way to filed/; the issue is the card, not both.
    func testAPromotedEntryIsNotASecondCard() {
        let item = BacklogItem(id: "c1", key: "C1", title: "Filed", issue: 87, body: "", path: "/p/docs/backlog/c1.md")
        XCTAssertFalse(BoardBuilder.build(BoardInput(localBacklog: [item])).contains { $0.isLocalBacklog })
    }
}
