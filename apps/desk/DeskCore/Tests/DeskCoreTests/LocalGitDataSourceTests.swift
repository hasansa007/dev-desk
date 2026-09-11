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

    /// Runs git and returns its stdout, optionally feeding stdin — for plumbing like `hash-object --stdin`.
    @discardableResult
    func gitOutput(_ arguments: [String], stdin: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + arguments
        process.currentDirectoryURL = url
        let out = Pipe()
        let input = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func writeScript(_ name: String, _ body: String) throws -> URL {
        let script = url.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}

final class LocalGitDataSourceTests: XCTestCase {
    private let issueList = "gh issue list --repo acme/app --state open --limit 200 --json number,title,labels,milestone,updatedAt,body,url"
    private let openPRs = "gh pr list --repo acme/app --state open --limit 100 --json number,title,headRefName,isCrossRepository,reviewDecision,isDraft,url,body"
    private let activeAuth = "gh auth status --active --hostname github.com"
    private let plainAuth = "gh auth status --hostname github.com"

    private func githubReadyRunner(root: URL) -> FakeRunner {
        FakeRunner([
            FakeRunner.gitRead("rev-parse --show-toplevel"): .ok(root.path + "\n"),
            FakeRunner.gitRead("rev-parse --abbrev-ref HEAD"): .ok("main\n"),
            FakeRunner.gitRead("remote get-url origin"): .ok("git@github.com:acme/app.git\n"),
            FakeRunner.gitRead("rev-parse --short HEAD"): .ok("abc1234\n"),
            FakeRunner.partialCloneRead: .failed(1),
            FakeRunner.promisorRead: .failed(1),
            FakeRunner.gitRead("branch -r --format=%(refname:short)"): .ok("origin\norigin/main\n"),
            FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"): .ok("refs/heads/main\n"),
            FakeRunner.gitRead("rev-parse --verify --quiet refs/heads/main"): .ok("0123456789abcdef0123456789abcdef01234567\n"),
            FakeRunner.gitRead("rev-parse --short refs/heads/main"): .ok("abc1234\n"),
            activeAuth: .ok("github.com\n  ✓ Logged in to github.com account octo (keyring)\n"),
            issueList: .ok("[]"),
            openPRs: .ok("[]"),
            "gh pr list --repo acme/app --state merged --limit 10 --json number,title,headRefName,isCrossRepository,mergedAt,url": .ok("[]"),
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

    private func pullRequestJSON(_ numbers: ClosedRange<Int>) -> String {
        let prs = numbers.map {
            #"{"number":\#($0),"title":"PR \#($0)","headRefName":"b\#($0)","isCrossRepository":false,"reviewDecision":"","isDraft":false,"url":"https://github.com/acme/app/pull/\#($0)","body":""}"#
        }
        return "[" + prs.joined(separator: ",") + "]"
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
                       + "Active milestone: v2, nearest due date 2026-10-01.")
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
        let (github, snapshot) = try await githubConnection { [activeAuth] in
            $0.script(activeAuth, .failed(127, stderr: "env: gh: No such file or directory"))
        }
        XCTAssertEqual(github, Connection(id: "github", name: "GitHub", state: .unavailable, label: "gh not installed"))
        XCTAssertEqual(snapshot.boardNote, "GitHub is unavailable (gh not installed), so only local branches are shown.")
        XCTAssertEqual(snapshot.roadmap.unavailableReason, "GitHub is unavailable (gh not installed), so the roadmap can't be read.")
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "GitHub account" }?.value, "gh not installed")
    }

    func testSignedOutGhIsReportedAsNotSignedInWithoutRetrying() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(activeAuth, .failed(1, stderr: "You are not logged into any GitHub hosts. To log in, run: gh auth login"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.connections.first { $0.id == "github" }?.label, "not signed in to GitHub")
        XCTAssertFalse(runner.keys.contains(plainAuth))
    }

    func testActiveAccountDecidesEvenWhenAnotherAccountIsBroken() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(plainAuth, .failed(1, stderr: "X Failed to log in to github.com account old-account (keyring)"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.connections.first { $0.id == "github" }?.state, .connected)
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "GitHub account" }?.value, "octo")
        XCTAssertFalse(runner.keys.contains(plainAuth))
    }

    func testOlderGhWithoutTheActiveFlagFallsBackToThePlainStatus() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(activeAuth, .failed(1, stderr: "unknown flag: --active\n\nUsage:  gh auth status [flags]\n"))
        runner.script(plainAuth, .ok("github.com\n  ✓ Logged in to github.com as octo (oauth_token)\n"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.connections.first { $0.id == "github" }?.state, .connected)
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "GitHub account" }?.value, "octo")
        XCTAssertEqual(runner.keys.filter { $0.hasPrefix("gh auth status") }, [activeAuth, plainAuth])
    }

    func testNonGitHubRemoteIsNamedAsSuch() async throws {
        let (github, _) = try await githubConnection { $0.script(FakeRunner.gitRead("remote get-url origin"), .ok("git@gitlab.com:acme/app.git\n")) }
        XCTAssertEqual(github?.label, "the remote is not on GitHub")
    }

    func testMissingRemoteIsNamedAsSuch() async throws {
        let (github, snapshot) = try await githubConnection {
            $0.script(FakeRunner.gitRead("remote get-url origin"), .failed(2, stderr: "error: No such remote 'origin'"))
        }
        XCTAssertEqual(github?.label, "no GitHub remote")
        XCTAssertEqual(snapshot.projectFacts.first { $0.key == "Remote" }?.value, "none")
    }

    func testDisabledIssuesKeepPullRequestsOnTheBoardAndSayWhy() async throws {
        let (github, snapshot) = try await githubConnection { [issueList, openPRs, pullRequestJSON] in
            $0.script(issueList, .failed(1, stderr: "the 'acme/app' repository has disabled issues\n"))
            $0.script(openPRs, .ok(pullRequestJSON(5...5)))
        }
        XCTAssertEqual(github?.state, .connected)
        XCTAssertEqual(snapshot.board.value?.map(\.id), ["pr:5"])
        XCTAssertTrue(snapshot.boardNote.hasSuffix(
            " Open issues could not be read (the 'acme/app' repository has disabled issues), so only pull requests and branches are shown."))
        XCTAssertEqual(snapshot.roadmap.unavailableReason,
                       "Open issues could not be read (the 'acme/app' repository has disabled issues), so the roadmap can't be read.")
    }

    func testFailedPullRequestReadMakesGitHubUnavailable() async throws {
        let (github, snapshot) = try await githubConnection { [openPRs] in $0.script(openPRs, .failed(1, stderr: "HTTP 502: Bad Gateway\n")) }
        XCTAssertEqual(github?.label, "could not read open pull requests: HTTP 502: Bad Gateway")
        XCTAssertEqual(snapshot.boardNote, "GitHub is unavailable (could not read open pull requests: HTTP 502: Bad Gateway), so only local branches are shown.")
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

    func testASymlinkedReportIsIgnoredAndItsContentsNeverAppear() async throws {
        let folder = try TempGitRepo()
        try folder.write("docs/survey/2026-09-10.md", "## CONFIRMED (1)\n- Real bug · a.swift:1\n")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("secret-\(UUID().uuidString).md")
        try "## CONFIRMED (1)\n- Leaked secret · /etc/passwd:1\n".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: folder.url.appendingPathComponent("docs/survey/2026-09-20.md"), withDestinationURL: outside)

        let report = try await LocalGitDataSource(root: folder.url, runner: githubReadyRunner(root: folder.url)).load().findings.value
        XCTAssertEqual(report?.runs.map(\.id), ["2026-09-10"])
        XCTAssertFalse(report?.findings.contains { $0.title == "Leaked secret" } ?? true, "a symlinked report must not be read")
    }

    func testAnOversizedReportIsRefusedButLabelled() async throws {
        let folder = try TempGitRepo()
        try folder.write("docs/survey/2026-09-10.md", "## CONFIRMED (1)\n- Real bug · a.swift:1\n")
        try folder.write("docs/survey/2026-09-30.md", "## CONFIRMED (1)\n- x · a.swift:1\n" + String(repeating: "a", count: 1_048_600))

        let report = try await LocalGitDataSource(root: folder.url, runner: githubReadyRunner(root: folder.url)).load().findings.value
        XCTAssertEqual(report?.runs.map(\.label), ["2026-09-30 · Report too large to read (over 1 MB)", "2026-09-10"])
        XCTAssertEqual(report?.findings.map(\.runID), ["2026-09-10"], "no findings are parsed from the oversized report")
    }

    func testAHostileTextconvDriverDoesNotRunOnOpen() async throws {
        let repo = try TempGitRepo()
        try repo.git("init", "-q", "-b", "main")
        let marker = repo.url.appendingPathComponent("PWNED")
        let driver = repo.url.appendingPathComponent("driver.sh")
        try "#!/bin/sh\ntouch \"\(marker.path)\"\ncat \"$1\"\n".write(to: driver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: driver.path)
        try repo.write(".gitattributes", "* diff=evil\n")
        try repo.write("file.txt", "one\n")
        try repo.commitAll("initial")
        try repo.git("config", "diff.evil.textconv", driver.path)
        try repo.git("checkout", "-q", "-b", "feature")
        try repo.write("file.txt", "two\n")
        try repo.commitAll("change")

        // Control: under the repo's own config the driver runs, proving the attack is real.
        try repo.git("diff", "main...feature")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "textconv should run under the repo's own config")
        try FileManager.default.removeItem(at: marker)

        _ = try await LocalGitDataSource(root: repo.url).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "opening the folder must not run the repo's textconv driver")
    }

    func testAHostileSignatureVerifierDoesNotRunOnOpen() async throws {
        let repo = try TempGitRepo()
        try repo.git("init", "-q", "-b", "main")
        try repo.write("README.md", "one\n")
        try repo.commitAll("initial")
        try repo.git("checkout", "-q", "-b", "feature")
        try repo.write("README.md", "two\n")
        try repo.commitAll("change")

        // Give the feature commit a PGP-looking signature header so log.showSignature triggers verification.
        var lines = try repo.gitOutput(["cat-file", "commit", "refs/heads/feature"]).components(separatedBy: "\n")
        let committer = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("committer ") })
        lines.insert(contentsOf: ["gpgsig -----BEGIN PGP SIGNATURE-----", " ", " aGVsbG8=", " -----END PGP SIGNATURE-----"], at: committer + 1)
        let sha = try repo.gitOutput(["hash-object", "-t", "commit", "-w", "--stdin"], stdin: lines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try repo.git("update-ref", "refs/heads/feature", sha)

        let marker = repo.url.appendingPathComponent("PWNED")
        let verifier = try repo.writeScript("gpg.sh", "touch \"\(marker.path)\"\nexit 0\n")
        try repo.git("config", "log.showSignature", "true")
        try repo.git("config", "gpg.program", verifier.path)

        // Control: under the repo's own config the verifier runs, proving the attack is real.
        _ = try repo.gitOutput(["log", "-1", "--show-signature", "refs/heads/feature"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "the verifier should run under the repo's own config")
        try FileManager.default.removeItem(at: marker)

        _ = try await LocalGitDataSource(root: repo.url).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "opening the folder must not run the repo's signature verifier")
    }

    /// A genuine blob:none partial clone of `source`: its local `feature` branch adds a blob the clone never fetched, so diffing it must lazy-fetch.
    private func partialCloneMissingABlob() throws -> (source: TempGitRepo, clone: TempGitRepo) {
        let source = try TempGitRepo()
        try source.git("init", "-q", "-b", "main")
        try source.write("README.md", "hi\n")
        try source.commitAll("initial")
        try source.git("checkout", "-q", "-b", "feature")
        try source.write("f.txt", "x\n")
        try source.commitAll("change")
        try source.git("checkout", "-q", "main")
        try source.git("config", "uploadpack.allowFilter", "true")
        let clone = try TempGitRepo()
        try source.git("clone", "-q", "--no-checkout", "--filter=blob:none", "file://\(source.url.path)", clone.url.path)
        try clone.git("branch", "-q", "feature", "origin/feature")
        return (source, clone)
    }

    /// Objects the repo lacks; `--missing=print` lists them without fetching.
    private func missingObjects(in repo: TempGitRepo) throws -> Int {
        try repo.gitOutput(["rev-list", "--objects", "--missing=print", "--all"]).split(separator: "\n").filter { $0.hasPrefix("?") }.count
    }

    /// Lazy fetch stays on (GIT_NO_LAZY_FETCH=0, as on git before 2.44), so only the gate stands between a read and the remote's uploadpack.
    private func assertLiveLazyFetchIsRefused(file: StaticString = #filePath, line: UInt = #line,
                                              _ markAsPartial: (TempGitRepo) throws -> Void) async throws {
        let fixture = try partialCloneMissingABlob()
        let clone = fixture.clone
        let marker = clone.url.appendingPathComponent("FETCHED")
        let uploadpack = try clone.writeScript("uploadpack.sh", "touch \"\(marker.path)\"\nexit 1\n")
        try clone.git("config", "remote.origin.uploadpack", uploadpack.path)
        try markAsPartial(clone)
        let missing = try missingObjects(in: clone)
        XCTAssertGreaterThan(missing, 0, "the clone must lack a blob, or no read could fetch", file: file, line: line)

        // Control: the app's own hardened diff, run without the gate, fetches the missing blob through the uploadpack.
        let lazyFetchOn = ProcessRunner(extraEnvironment: ["GIT_NO_LAZY_FETCH": "0"])
        _ = try await lazyFetchOn.run("git", GitCommand.read(["diff", "--no-color", "--no-ext-diff", "--no-textconv", "-U3",
                                                              "refs/heads/main...refs/heads/feature"]), in: clone.url, timeout: CommandTimeout.git)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "the attack must be live: an ungated read runs the uploadpack", file: file, line: line)
        try? FileManager.default.removeItem(at: marker)
        XCTAssertEqual(try missingObjects(in: clone), missing, "the failed fetch left the blob missing", file: file, line: line)

        let snapshot = try await LocalGitDataSource(root: clone.url, runner: lazyFetchOn).load()
        XCTAssertEqual(snapshot.board.unavailableReason, LocalGitDataSource.partialCloneReason, file: file, line: line)
        XCTAssertEqual(snapshot.boardNote, "", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the gate must stop every read that could fetch", file: file, line: line)
        withExtendedLifetime(fixture.source) {}
    }

    /// Only remote.origin.promisor marks the clone: git 2.50 never writes extensions.partialClone, and an older git's copy is removed.
    private func markAsPromisorOnly(_ clone: TempGitRepo, _ value: String) throws {
        try? clone.git("config", "--unset", "extensions.partialClone")
        XCTAssertEqual(try clone.gitOutput(["config", "--get", "extensions.partialClone"]), "", "the extension must be unset for this case")
        try clone.git("config", "remote.origin.promisor", value)
    }

    func testAPartialCloneIsRefusedAndItsUploadpackNeverRuns() async throws {
        try await assertLiveLazyFetchIsRefused { clone in
            try clone.git("config", "--unset-all", "remote.origin.promisor")
            try clone.git("config", "extensions.partialClone", "origin")
            XCTAssertEqual(try clone.gitOutput(["config", "--get-regexp", "^remote\\..*\\.promisor$"]), "", "only the extension marks this clone")
        }
    }

    func testAPromisorRemoteIsRefusedEvenWithoutThePartialCloneExtension() async throws {
        try await assertLiveLazyFetchIsRefused { try markAsPromisorOnly($0, "true") }
    }

    func testAPromisorSetToANonZeroIntegerIsRefusedBecauseGitReadsItAsTrue() async throws {
        try await assertLiveLazyFetchIsRefused { try markAsPromisorOnly($0, "2") }
    }

    func testTheGateFollowsGitsOwnBooleanRule() async throws {
        let repo = try TempGitRepo()
        try repo.git("init", "-q", "-b", "main")
        try repo.write("README.md", "hi\n")
        try repo.commitAll("initial")
        func board(promisor value: String) async throws -> Surface<[DeskTask]> {
            try repo.git("config", "remote.origin.promisor", value)
            return try await LocalGitDataSource(root: repo.url).load().board
        }
        for value in ["42", "-1", "1k"] {
            let refused = try await board(promisor: value)
            XCTAssertEqual(refused.unavailableReason, LocalGitDataSource.partialCloneReason, "git reads promisor=\(value) as true")
        }
        for value in ["", "0"] {
            let read = try await board(promisor: value)
            XCTAssertNotNil(read.value, "git reads promisor=\"\(value)\" as false, so the repo is read")
        }
        let invalid = try await board(promisor: "maybe")
        XCTAssertEqual(invalid.unavailableReason, LocalGitDataSource.remotesUncheckedReason, "git rejects the value, so the gate can't tell")
    }

    func testAPromisorRemoteSetToFalseIsNotRefused() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.promisorRead, .ok("remote.origin.promisor false\n"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertNotEqual(snapshot.board.unavailableReason, LocalGitDataSource.partialCloneReason)
        XCTAssertNotNil(snapshot.board.value)
    }

    func testPromisorConfigSkipsEveryBranchRead() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.promisorRead, .ok("remote.origin.promisor true\n"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.board.unavailableReason, LocalGitDataSource.partialCloneReason)
        XCTAssertFalse(runner.keys.contains { $0.contains("for-each-ref") || $0.contains("rev-list") || $0.contains(" log ") },
                       "no branch read may run for a promisor remote")
    }

    func testPartialCloneConfigSkipsEveryBranchRead() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.partialCloneRead, .ok("origin\n"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.board.unavailableReason, LocalGitDataSource.partialCloneReason)
        XCTAssertFalse(runner.keys.contains { $0.contains("for-each-ref") || $0.contains("rev-list") || $0.contains(" log ") },
                       "no branch read may run for a partial clone")
    }

    func testAnEmptyPartialCloneValueStillCountsAsSet() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.partialCloneRead, .ok("\n"))
        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.board.unavailableReason, LocalGitDataSource.partialCloneReason, "exit 0 means the key is set, whatever its value")
    }

    func testTheGateFailsClosedWhenAConfigReadGivesNoClearAnswer() async throws {
        let badBool = "fatal: bad boolean config value 'maybe' for 'remote.origin.promisor'\n"
        let timeout = CommandError.timedOut(tool: "git", seconds: CommandTimeout.git)
        let outcomes: [(String, (FakeRunner) -> Void)] = [
            ("promisor read exits 128", { $0.script(FakeRunner.promisorRead, .failed(128, stderr: badBool)) }),
            ("promisor read times out", { $0.script(FakeRunner.promisorRead, throwing: timeout) }),
            ("promisor read is killed by SIGHUP", { $0.script(FakeRunner.promisorRead, .failed(128 + SIGHUP)) }),
            ("promisor read exits 1 but writes stderr", { $0.script(FakeRunner.promisorRead, .failed(1, stderr: "error: unexpected\n")) }),
            ("promisor read succeeds but lists nothing", { $0.script(FakeRunner.promisorRead, .ok("")) }),
            ("partialClone read exits 128", { $0.script(FakeRunner.partialCloneRead, .failed(128, stderr: "fatal: bad config line 1\n")) }),
            ("partialClone read times out", { $0.script(FakeRunner.partialCloneRead, throwing: timeout) }),
        ]
        for (label, outcome) in outcomes {
            let folder = try TempGitRepo()
            let runner = githubReadyRunner(root: folder.url)
            outcome(runner)
            let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
            XCTAssertEqual(snapshot.board.unavailableReason, LocalGitDataSource.remotesUncheckedReason, label)
            XCTAssertEqual(snapshot.boardNote, "", label)
            XCTAssertFalse(runner.keys.contains { $0.contains("for-each-ref") || $0.contains("rev-list") || $0.contains(" log ") }, label)
        }
    }

    func testACancelledGateReadIsRethrownSoTheLoadIsDroppedNotRefused() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.promisorRead, throwing: CancellationError())
        do {
            _ = try await LocalGitDataSource(root: folder.url, runner: runner).load()
            XCTFail("a cancelled gate read must not come back as a refused snapshot")
        } catch is CancellationError {}
        XCTAssertFalse(runner.keys.contains { $0.contains("for-each-ref") }, "no branch read runs after a cancelled gate read")
    }

    func testGitLogFailureReasonIsEscapedForMarkdown() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"), .ok("refs/heads/main\nrefs/heads/spike\n"))
        runner.script(FakeRunner.gitRead("rev-list --count refs/heads/main..refs/heads/spike"), .ok("1\n"))
        runner.script(FakeRunner.gitRead("log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 refs/heads/main..refs/heads/spike"),
                      .failed(128, stderr: "fatal: [pwn](file:///Applications/Calculator.app)\n"))
        runner.script(FakeRunner.gitRead("diff --numstat --no-textconv refs/heads/main...refs/heads/spike"), .ok(""))
        runner.script(FakeRunner.gitRead("diff --no-color --no-ext-diff --no-textconv -U3 refs/heads/main...refs/heads/spike"), .ok(""))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let reason = try XCTUnwrap(snapshot.board.value?.first { $0.id == "branch:spike" }?.activity.unavailableReason)
        XCTAssertEqual(reason, "git log failed: fatal: \\[pwn\\](file:///Applications/Calculator.app)")
        XCTAssertFalse(reason.contains("[pwn]("), "the link must be escaped")
    }

    func testEveryGitReadIsHardenedAndDiffsDisableTextconv() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"), .ok("refs/heads/main\nrefs/heads/feat/12-x\n"))
        runner.script(FakeRunner.gitRead("rev-list --count refs/heads/main..refs/heads/feat/12-x"), .ok("1\n"))
        runner.script(FakeRunner.gitRead("log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 refs/heads/main..refs/heads/feat/12-x"), .ok(""))
        runner.script(FakeRunner.gitRead("diff --numstat --no-textconv refs/heads/main...refs/heads/feat/12-x"), .ok(""))
        runner.script(FakeRunner.gitRead("diff --no-color --no-ext-diff --no-textconv -U3 refs/heads/main...refs/heads/feat/12-x"), .ok(""))

        _ = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let gitKeys = runner.keys.filter { $0.hasPrefix("git ") }
        XCTAssertFalse(gitKeys.isEmpty)
        for key in gitKeys {
            XCTAssertTrue(key.hasPrefix("git -c core.fsmonitor= -c core.hooksPath=/dev/null -c diff.external= "), key)
            XCTAssertTrue(key.contains("-c log.showSignature=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false "), key)
        }
        XCTAssertTrue(runner.keys.contains { $0.contains("diff --numstat --no-textconv ") })
        XCTAssertTrue(runner.keys.contains { $0.contains("--no-ext-diff --no-textconv -U3 ") })
    }

    func testBranchFanOutIsCappedAtTwoHundredAndTheNoteSaysSo() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        let refs = (["refs/heads/main"] + (1...250).map { "refs/heads/b\($0)" }).joined(separator: "\n") + "\n"
        runner.script(FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"), .ok(refs))
        for i in 1...250 {
            runner.script(FakeRunner.gitRead("rev-list --count refs/heads/main..refs/heads/b\(i)"), .ok("1\n"))
            runner.script(FakeRunner.gitRead("log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 refs/heads/main..refs/heads/b\(i)"), .ok(""))
            runner.script(FakeRunner.gitRead("diff --numstat --no-textconv refs/heads/main...refs/heads/b\(i)"), .ok(""))
            runner.script(FakeRunner.gitRead("diff --no-color --no-ext-diff --no-textconv -U3 refs/heads/main...refs/heads/b\(i)"), .ok(""))
        }

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertEqual(snapshot.board.value?.filter { $0.id.hasPrefix("branch:") }.count, 200)
        XCTAssertTrue(snapshot.boardNote.hasSuffix(" Showing 200 of 250 local branches."), snapshot.boardNote)
        XCTAssertEqual(runner.keys.filter { $0.contains("rev-list --count") }.count, 200, "only the 200 newest branches are processed")
    }

    func testIssueBranchReadsItsDiffAndItsPipelineStateFile() async throws {
        let folder = try TempGitRepo()
        try folder.write(".dev/feat-12-x.json", #"{"phase":9,"phase_group":"coding","tier":"standard"}"#)
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"), .ok("refs/heads/main\nrefs/heads/feat/12-x\n"))
        runner.script(FakeRunner.gitRead("rev-list --count refs/heads/main..refs/heads/feat/12-x"), .ok("2\n"))
        runner.script(FakeRunner.gitRead("log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 refs/heads/main..refs/heads/feat/12-x"),
                      .ok("abc1234\u{1F}Ada\u{1F}2026-09-11T09:00:00Z\u{1F}Start\n"))
        runner.script(FakeRunner.gitRead("diff --numstat --no-textconv refs/heads/main...refs/heads/feat/12-x"), .ok("1\t0\tA.swift\n"))
        runner.script(FakeRunner.gitRead("diff --no-color --no-ext-diff --no-textconv -U3 refs/heads/main...refs/heads/feat/12-x"),
                      .ok("diff --git a/A.swift b/A.swift\n--- /dev/null\n+++ b/A.swift\n@@ -0,0 +1 @@\n+x\n"))
        runner.script(issueList, .ok(#"[{"number":12,"title":"Crash","labels":[],"milestone":null,"updatedAt":"2026-09-01T00:00:00Z","body":"","url":"https://github.com/acme/app/issues/12"}]"#))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let task = try XCTUnwrap(snapshot.board.value?.first { $0.id == "12" })
        XCTAssertEqual(task.column, .inProgress)
        XCTAssertEqual(task.cardNote, "Phase 9 · coding · advisory")
        XCTAssertEqual(task.changes.value?.files.map(\.id), ["A.swift"])
        XCTAssertEqual(task.changes.value?.diffs["A.swift"]?.hunks.first?.lines, [DiffLine(.addition, "x")])
        XCTAssertEqual(task.branchLine, "feat/12-x · base main@abc1234")
    }

    func testChecksAreReadForTheTenNewestPullRequestsAndNeverFakeAnEmptyList() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(openPRs, .ok(pullRequestJSON(1...12)))
        runner.script("gh pr checks 1 --repo acme/app --json name,bucket,link",
                      CommandResult(status: 8, stdout: #"[{"name":"ci","bucket":"pending","link":""}]"#, stderr: ""))
        runner.script("gh pr checks 3 --repo acme/app --json name,bucket,link", .failed(1, stderr: "no checks reported on the 'b3' branch\n"))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let evidence = Dictionary(uniqueKeysWithValues: (snapshot.board.value ?? []).map { ($0.id, $0.evidence) })
        XCTAssertEqual(runner.keys.filter { $0.hasPrefix("gh pr checks ") }.count, 10)
        XCTAssertEqual(evidence["pr:1"]?.value?.checks,
                       [CheckResult(id: "pr1-0", name: "ci", outcome: .warning, outcomeLabel: "pending", revisionLabel: "PR #1")])
        XCTAssertEqual(evidence["pr:2"], .unavailable("gh pr checks failed: unscripted"))
        XCTAssertEqual(evidence["pr:3"], .available(Evidence(isDemo: false)))
        XCTAssertEqual(evidence["pr:11"], .unavailable("Checks are read for the 10 newest open pull requests; this one was not read."))
        XCTAssertEqual(evidence["pr:12"], .unavailable("Checks are read for the 10 newest open pull requests; this one was not read."))
    }

    func testFailedLogAndDiffReadsAreUnavailableRatherThanEmpty() async throws {
        let folder = try TempGitRepo()
        let runner = githubReadyRunner(root: folder.url)
        runner.script(FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"), .ok("refs/heads/main\nrefs/heads/spike\n"))
        runner.script(FakeRunner.gitRead("rev-list --count refs/heads/main..refs/heads/spike"), .ok("3\n"))
        runner.script(FakeRunner.gitRead("log --format=%h%x1f%an%x1f%aI%x1f%s -n 50 refs/heads/main..refs/heads/spike"),
                      .failed(128, stderr: "fatal: bad object refs/heads/spike\n"))
        runner.script(FakeRunner.gitRead("diff --numstat --no-textconv refs/heads/main...refs/heads/spike"), .ok("1\t0\tA.swift\n"))
        runner.script(FakeRunner.gitRead("diff --no-color --no-ext-diff --no-textconv -U3 refs/heads/main...refs/heads/spike"),
                      .failed(128, stderr: "fatal: unable to read tree 1234567\n"))

        let snapshot = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        let task = try XCTUnwrap(snapshot.board.value?.first { $0.id == "branch:spike" })
        XCTAssertEqual(task.cardBadge, StatusBadge(.neutral, "3 commits ahead"))
        XCTAssertEqual(task.activity, .unavailable("git log failed: fatal: bad object refs/heads/spike"))
        XCTAssertEqual(task.changes, .unavailable("git diff failed: fatal: unable to read tree 1234567"))
    }

    func testRevisionArgumentsAreFullyQualifiedSoNoBranchNameBecomesAnOption() async throws {
        let folder = try TempGitRepo()
        let runner = FakeRunner([
            FakeRunner.gitRead("rev-parse --show-toplevel"): .ok(folder.url.path + "\n"),
            FakeRunner.gitRead("rev-parse --abbrev-ref HEAD"): .ok("--output=/tmp/pwned\n"),
            FakeRunner.partialCloneRead: .failed(1),
            FakeRunner.promisorRead: .failed(1),
            FakeRunner.gitRead("for-each-ref --format=%(refname) --sort=-committerdate refs/heads"): .ok("refs/heads/--output=/tmp/pwned\nrefs/heads/feature\n"),
            FakeRunner.gitRead("rev-list --count refs/heads/--output=/tmp/pwned..refs/heads/feature"): .ok("0\n"),
        ])
        _ = try await LocalGitDataSource(root: folder.url, runner: runner).load()
        XCTAssertTrue(runner.keys.contains(FakeRunner.gitRead("rev-parse --short refs/heads/--output=/tmp/pwned")))
        XCTAssertTrue(runner.keys.contains(FakeRunner.gitRead("rev-list --count refs/heads/--output=/tmp/pwned..refs/heads/feature")))
        for key in runner.keys where key.hasPrefix("git ") {
            XCTAssertFalse(key.split(separator: " ").contains { $0.hasPrefix("--output") }, key)
        }
    }

    func testRealBranchNamedWithALeadingDashIsReadAsARef() async throws {
        let repo = try TempGitRepo()
        try repo.git("init", "-q", "-b", "main")
        try repo.write("README.md", "hello\n")
        try repo.commitAll("initial")
        try repo.git("checkout", "-q", "-b", "scratch")
        try repo.write("Dash.swift", "let dash = 1\n")
        try repo.commitAll("dash work")
        try repo.git("update-ref", "refs/heads/-x", "HEAD")
        try repo.git("checkout", "-q", "main")
        try repo.git("branch", "-q", "-D", "scratch")

        let snapshot = try await LocalGitDataSource(root: repo.url).load()
        let task = try XCTUnwrap(snapshot.board.value?.first { $0.id == "branch:-x" })
        XCTAssertEqual(task.cardBadge, StatusBadge(.neutral, "1 commit ahead"))
        XCTAssertEqual(task.changes.value?.files.map(\.id), ["Dash.swift"])
    }

    private func boardReason(toplevel result: CommandResult) async throws -> String? {
        let folder = try TempGitRepo()
        let runner = FakeRunner([FakeRunner.gitRead("rev-parse --show-toplevel"): result])
        return try await LocalGitDataSource(root: folder.url, runner: runner).load().board.unavailableReason
    }

    func testMissingGitAndMissingCommandLineToolsAreNamed() async throws {
        let missingGit = try await boardReason(toplevel: .failed(127, stderr: "env: git: No such file or directory\n"))
        XCTAssertEqual(missingGit, "Git is not installed, so this folder can't be read.")
        let missingTools = try await boardReason(toplevel: .failed(1, stderr:
            "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), missing xcrun at: /Library/Developer/CommandLineTools/usr/bin/xcrun\n"))
        XCTAssertEqual(missingTools, "The Xcode command line tools are missing, so git can't run. Install them with xcode-select --install.")
    }

    func testOwnershipRefusalNamesTheCommandThatTrustsTheFolder() async throws {
        let reason = try await boardReason(toplevel: .failed(128, stderr:
            "fatal: detected dubious ownership in repository at '/Volumes/shared/app'\nTo add an exception for this directory, call:\n\n\tgit config --global --add safe.directory /Volumes/shared/app\n"))
        XCTAssertEqual(reason, "Git refuses to read this folder because another user owns it (dubious ownership). "
                       + "To trust it, run: git config --global --add safe.directory /Volumes/shared/app")
    }

    func testGenuineNonRepositoryKeepsItsTextAndOtherFailuresSayWhatHappened() async throws {
        let notRepository = try await boardReason(toplevel: .failed(128, stderr: "fatal: not a git repository (or any of the parent directories): .git\n"))
        XCTAssertEqual(notRepository, "This folder is not a git repository.")
        let bare = try await boardReason(toplevel: .failed(128, stderr: "fatal: this operation must be run in a work tree\n"))
        XCTAssertEqual(bare, "git could not read this folder: fatal: this operation must be run in a work tree")
        let folder = try TempGitRepo()
        let timedOut = try await LocalGitDataSource(root: folder.url, runner: ThrowingRunner(error: CommandError.timedOut(tool: "git", seconds: 15))).load()
        XCTAssertEqual(timedOut.board.unavailableReason, "git could not read this folder: git did not finish within 15 seconds")
    }

    func testMaliciousGitStderrInAToplevelReasonIsEscapedForMarkdown() async throws {
        let reason = try await boardReason(toplevel: .failed(128, stderr: "fatal: bad config value for 'diff.renameLimit': [x](file:///y)\n"))
        XCTAssertEqual(reason, "git could not read this folder: fatal: bad config value for 'diff.renameLimit': \\[x\\](file:///y)")
        XCTAssertFalse(reason!.contains("[x]("), "the link must be escaped")
    }
}
