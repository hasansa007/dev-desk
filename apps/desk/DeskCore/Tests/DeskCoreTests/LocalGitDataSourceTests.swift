import Foundation
import XCTest
@testable import DeskCore

/// A temporary folder that git commands can run in; removed when released.
final class TempGitRepo {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("deskcore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ path: String, _ text: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + arguments
        process.currentDirectoryURL = url
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "TempGitRepo", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"])
        }
    }

    func commitAll(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }
}

private final class SlowCountingRunner: CommandRunner {
    private let lock = NSLock()
    private var running = 0
    private var highest = 0

    var peak: Int { lock.withLock { highest } }

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        lock.withLock {
            running += 1
            highest = max(highest, running)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        lock.withLock { running -= 1 }
        return CommandResult(status: 0, stdout: "", stderr: "")
    }
}

final class LocalGitDataSourceTests: XCTestCase {
    private let issueList = "gh issue list --repo acme/app --state open --limit 200 --json number,title,labels,milestone,updatedAt,body,url"
    private let openPRs = "gh pr list --repo acme/app --state open --limit 100 --json number,title,headRefName,reviewDecision,isDraft,url,body"

    private func githubReadyRunner(root: URL) -> FakeRunner {
        FakeRunner([
            "git rev-parse --show-toplevel": .ok(root.path + "\n"),
            "git rev-parse --abbrev-ref HEAD": .ok("main\n"),
            "git remote get-url origin": .ok("git@github.com:acme/app.git\n"),
            "git rev-parse --short HEAD": .ok("abc1234\n"),
            "git branch -r --format=%(refname:short)": .ok("origin\norigin/main\n"),
            "git for-each-ref --format=%(refname:short) refs/heads": .ok("main\n"),
            "git rev-parse --verify --quiet refs/heads/main": .ok("0123456789abcdef0123456789abcdef01234567\n"),
            "git rev-parse --short main": .ok("abc1234\n"),
            "gh auth status --hostname github.com": .ok("github.com\n  ✓ Logged in to github.com account octo (keyring)\n"),
            issueList: .ok("[]"),
            openPRs: .ok("[]"),
            "gh pr list --repo acme/app --state merged --limit 10 --json number,title,headRefName,mergedAt,url": .ok("[]"),
            "gh api repos/acme/app/milestones?state=open": .ok("[]"),
            "which claude": .ok("/usr/local/bin/claude\n"),
        ])
    }

    private func githubConnection(_ adjust: (FakeRunner) -> Void) async throws -> (Connection?, ProjectSnapshot) {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        adjust(runner)
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        return (snapshot.connections.first { $0.id == "github" }, snapshot)
    }

    func testRealRepositoryShowsItsFeatureBranchWithoutGitHub() async throws {
        let repo = try TempGitRepo()
        try repo.git("init", "-q", "-b", "main")
        try repo.write("README.md", "hello\n")
        try repo.commitAll("initial")
        try repo.git("checkout", "-q", "-b", "feature/x")
        try repo.write("Sources/Feature.swift", "let x = 1\n")
        try repo.commitAll("add feature")

        let snapshot = try await LocalGitDataSource(root: repo.url).load()
        let task = try XCTUnwrap(snapshot.board.value?.first { $0.id == "branch:feature/x" })
        XCTAssertEqual(task.column, .inProgress)
        XCTAssertEqual(task.cardBadge, StatusBadge(.neutral, "1 commit ahead"))
        XCTAssertEqual(task.activity.value?.count, 1)
        XCTAssertEqual(task.changes.value?.files.map(\.id), ["Sources/Feature.swift"])
        XCTAssertEqual(task.changes.value?.diffs["Sources/Feature.swift"]?.hunks.first?.lines, [DiffLine(.addition, "let x = 1")])
        XCTAssertTrue(snapshot.boardNote.hasPrefix("GitHub is unavailable"))
        XCTAssertEqual(snapshot.boardNote, "GitHub is unavailable (no GitHub remote), so only local branches are shown.")
        XCTAssertEqual(snapshot.connections.first { $0.id == "github" }?.state, .unavailable)
        XCTAssertFalse(snapshot.isDemo)
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "Base branch" }?.value, "main")
    }

    func testPlainFolderIsNotAGitRepository() async throws {
        let folder = try TempGitRepo()
        let snapshot = try await LocalGitDataSource(root: folder.url).load()
        let reason = "This folder is not a git repository."
        XCTAssertEqual(snapshot.board.unavailableReason, reason)
        XCTAssertEqual(snapshot.findings.unavailableReason, reason)
        XCTAssertEqual(snapshot.roadmap.unavailableReason, reason)
        XCTAssertEqual(snapshot.decisions.unavailableReason, reason)
    }

    func testGitHubReadyRepositoryReadsDecisionsNewestFirst() async throws {
        let folder = try TempGitRepo()
        try folder.write("docs/adr/0001-x.md", "# 0001 — Use x\n\nStatus: Accepted\nDate: 2026-09-01\n\n## Decision\n\nUse x.\n")
        try folder.write("docs/adr/0010-y.md", "# 0010 — Use y\n\nStatus: Proposed\nDate: 2026-09-05\n")
        try folder.write("docs/adr/0002-z.md", "# 0002 — Use z\n\nStatus: Superseded\nDate: 2026-09-02\n")
        try folder.write("docs/adr/README.md", "# ADRs\n")
        let runner = githubReadyRunner(root: folder.url)

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let decisions = try XCTUnwrap(snapshot.decisions.value)
        XCTAssertEqual(decisions.map(\.id), ["0010-y", "0002-z", "0001-x"])
        XCTAssertEqual(decisions.last?.listMeta, "ADR 0001 · Accepted · 2026-09-01")
        XCTAssertEqual(decisions.last?.answer?.rationale, "Use x.")
        XCTAssertEqual(snapshot.connections.first { $0.id == "github" }, Connection(id: "github", name: "GitHub", state: .connected, label: "connected"))
        XCTAssertEqual(snapshot.board, .available([]))
        XCTAssertEqual(snapshot.findings, .available(FindingsReport(runs: [], findings: [])))
        XCTAssertEqual(snapshot.roadmap.value?.themes, [])
        XCTAssertTrue(runner.calls.allSatisfy { !$0.key.hasPrefix("gh ") || $0.timeout == CommandTimeout.gh })
        XCTAssertTrue(runner.calls.allSatisfy { !$0.key.hasPrefix("git ") || $0.timeout == CommandTimeout.git })
    }

    func testBoardNoteAndFactsNameTheActiveMilestoneAndAccount() async throws {
        let (_, snapshot) = try await githubConnection {
            $0.script("gh api repos/acme/app/milestones?state=open",
                      .ok(#"[{"title":"v2","due_on":"2026-10-01T07:00:00Z","created_at":"2026-08-01T00:00:00Z","open_issues":1,"closed_issues":1}]"#))
        }
        XCTAssertEqual(snapshot.boardNote, "Columns follow dev:kanban's rules: git decides In progress and Review, and the active milestone decides Queued. "
                       + "Active milestone: v2 (nearest due date (2026-10-01)).")
        XCTAssertEqual(snapshot.projectFacts, [
            KeyValue("Base branch", "main", monospaced: true),
            KeyValue("Base revision", "abc1234", monospaced: true),
            KeyValue("Remote", "github.com/acme/app", monospaced: true),
            KeyValue("Active milestone", "v2"),
            KeyValue("GitHub account", "octo"),
        ])
        XCTAssertEqual(snapshot.roadmap.value?.themes.map(\.title), ["Milestone · v2"])
    }

    func testNoMilestoneExplainsWhyInTheFacts() async throws {
        let (_, snapshot) = try await githubConnection { _ in }
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "Active milestone" }?.value, "none — no open milestone")
        XCTAssertTrue(snapshot.boardNote.hasSuffix(" No active milestone, so Queued is empty."))
    }

    func testMissingGhIsReportedAsNotInstalled() async throws {
        let (github, snapshot) = try await githubConnection {
            $0.script("gh auth status --hostname github.com", .failed(127, stderr: "env: gh: No such file or directory"))
        }
        XCTAssertEqual(github, Connection(id: "github", name: "GitHub", state: .unavailable, label: "gh not installed"))
        XCTAssertEqual(snapshot.boardNote, "GitHub is unavailable (gh not installed), so only local branches are shown.")
        XCTAssertEqual(snapshot.roadmap.unavailableReason, "GitHub is unavailable (gh not installed), so the roadmap can't be read.")
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "GitHub account" }?.value, "gh not installed")
    }

    func testSignedOutGhIsReportedAsNotSignedIn() async throws {
        let (github, _) = try await githubConnection {
            $0.script("gh auth status --hostname github.com", .failed(1, stderr: "You are not logged into any GitHub hosts. To log in, run: gh auth login"))
        }
        XCTAssertEqual(github?.label, "not signed in to GitHub")
    }

    func testNonGitHubRemoteIsNamedAsSuch() async throws {
        let (github, _) = try await githubConnection { $0.script("git remote get-url origin", .ok("git@gitlab.com:acme/app.git\n")) }
        XCTAssertEqual(github?.label, "the remote is not on GitHub")
    }

    func testMissingRemoteIsNamedAsSuch() async throws {
        let (github, snapshot) = try await githubConnection {
            $0.script("git remote get-url origin", .failed(2, stderr: "error: No such remote 'origin'"))
        }
        XCTAssertEqual(github?.label, "no GitHub remote")
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "Remote" }?.value, "none")
    }

    func testFailedIssueReadNamesTheFailure() async throws {
        let (github, snapshot) = try await githubConnection { [issueList] in $0.script(issueList, .failed(1, stderr: "HTTP 502: Bad Gateway\n")) }
        XCTAssertEqual(github?.label, "could not read open issues: HTTP 502: Bad Gateway")
        XCTAssertEqual(snapshot.boardNote, "GitHub is unavailable (could not read open issues: HTTP 502: Bad Gateway), so only local branches are shown.")
    }

    func testToolsAreDetectedAndNothingClaimsAnAgentConnection() async throws {
        let (_, snapshot) = try await githubConnection { _ in }
        XCTAssertEqual(snapshot.connections, [
            Connection(id: "codex", name: "Codex", state: .missing, label: "not found"),
            Connection(id: "claude", name: "Claude", state: .detected, label: "CLI found"),
            Connection(id: "gemini", name: "Gemini", state: .missing, label: "not found"),
            Connection(id: "github", name: "GitHub", state: .connected, label: "connected"),
        ])
        XCTAssertEqual(snapshot.connectionsNote, "Detected on this Mac. Dev Desk doesn't connect to agents yet.")
        XCTAssertEqual(snapshot.capabilities.providers, ["Codex", "Claude", "Gemini"])
        XCTAssertEqual(snapshot.capabilities.rows.map(\.name), ["Interactive terminal", "Resume an ended session", "Attach to an external session"])
        XCTAssertTrue(snapshot.capabilities.rows.allSatisfy { $0.values == [.notValidated, .notValidated, .notValidated] })
        XCTAssertEqual(snapshot.capabilities.note, "No agent integration has been validated. Capabilities will be read from a connection once one exists.")
        XCTAssertEqual(snapshot.insights, .unavailable("Insights needs a validated agent connection. None is set up, so this panel can't answer yet."))
    }

    func testFindingsListTheNewestReportFirst() async throws {
        let folder = try TempGitRepo()
        try folder.write("docs/survey/2026-09-01.md", "## CONFIRMED (1)\n- Old bug · a.swift:1\n")
        try folder.write("docs/survey/2026-09-10.md", "## CONFIRMED (1)\n- New bug · b.swift:2\n")
        try folder.write("docs/survey/notes.txt", "not a report")
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: githubReadyRunner(root: folder.url)).load()
        let report = try XCTUnwrap(snapshot.findings.value)
        XCTAssertEqual(report.runs, [SurveyRun(id: "2026-09-10", label: "2026-09-10", revision: nil),
                                     SurveyRun(id: "2026-09-01", label: "2026-09-01", revision: nil)])
        XCTAssertEqual(report.findings.map(\.id), ["2026-09-10-C1", "2026-09-01-C1"])
    }

    func testIssueBranchReadsItsDiffAndItsPipelineStateFile() async throws {
        let folder = try TempGitRepo()
        try folder.write(".dev/feat-12-x.json", #"{"phase":9,"phase_group":"coding","tier":"standard"}"#)
        let runner = githubReadyRunner(root: folder.url)
        runner.script("git for-each-ref --format=%(refname:short) refs/heads", .ok("main\nfeat/12-x\n"))
        runner.script("git rev-list --count main..feat/12-x", .ok("2\n"))
        runner.script("git log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 main..feat/12-x", .ok("abc1234\u{1F}Ada\u{1F}2026-09-11T09:00:00Z\u{1F}Start\n"))
        runner.script("git diff --numstat main...feat/12-x", .ok("1\t0\tA.swift\n"))
        runner.script("git diff --no-color --no-ext-diff -U3 main...feat/12-x", .ok("diff --git a/A.swift b/A.swift\n--- /dev/null\n+++ b/A.swift\n@@ -0,0 +1 @@\n+x\n"))
        runner.script(issueList, .ok(#"[{"number":12,"title":"Crash","labels":[],"milestone":null,"updatedAt":"2026-09-01T00:00:00Z","body":"","url":"https://github.com/acme/app/issues/12"}]"#))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let task = try XCTUnwrap(snapshot.board.value?.first { $0.id == "12" })
        XCTAssertEqual(task.column, .inProgress)
        XCTAssertEqual(task.cardNote, "Phase 9 · coding · advisory")
        XCTAssertEqual(task.changes.value?.files.map(\.id), ["A.swift"])
        XCTAssertEqual(task.changes.value?.diffs["A.swift"]?.hunks.first?.lines, [DiffLine(.addition, "x")])
        XCTAssertEqual(task.branchLine, "feat/12-x · base main@abc1234")
    }

    func testChecksAreReadForTenPullRequestsEvenWhilePending() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        let prs = (1...12).map {
            #"{"number":\#($0),"title":"PR \#($0)","headRefName":"b\#($0)","reviewDecision":"","isDraft":false,"url":"https://github.com/acme/app/pull/\#($0)","body":""}"#
        }
        runner.script(openPRs, .ok("[" + prs.joined(separator: ",") + "]"))
        runner.script("gh pr checks 1 --repo acme/app --json name,bucket,link",
                      CommandResult(status: 8, stdout: #"[{"name":"ci","bucket":"pending","link":""}]"#, stderr: ""))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(runner.keys.filter { $0.hasPrefix("gh pr checks ") }.count, 10)
        let checks = try XCTUnwrap(snapshot.board.value?.first { $0.id == "pr:1" }?.evidence.value?.checks)
        XCTAssertEqual(checks, [CheckResult(id: "pr1-0", name: "ci", outcome: .warning, outcomeLabel: "pending", revisionLabel: "PR #1")])
    }

    func testThrottledRunnerCapsConcurrentCommands() async {
        let slow = SlowCountingRunner()
        let throttled = ThrottledRunner(base: slow, limit: 3)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { _ = try? await throttled.run("git", ["status"], in: nil, timeout: 1) }
            }
        }
        XCTAssertLessThanOrEqual(slow.peak, 3)
        XCTAssertGreaterThanOrEqual(slow.peak, 2)
    }
}
