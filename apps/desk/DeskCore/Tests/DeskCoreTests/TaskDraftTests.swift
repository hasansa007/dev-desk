import XCTest
@testable import DeskCore

/// ADR 0045: Add Task's draft, destination and duplicate proposal, and the model filing where the tracker is.
final class TaskDraftTests: XCTestCase {

    // MARK: - The draft

    func testBulletsDropHowTheLineWasTypedAndSkipBlanks() {
        let text = "- first\n* second\n• third\n\n  1. fourth\n2) fifth\n- [ ] sixth\nplain seventh\n   "
        XCTAssertEqual(TaskDraft.bullets(from: text),
                       ["first", "second", "third", "fourth", "fifth", "sixth", "plain seventh"])
    }

    func testANumberThatIsTheTextIsKept() {
        XCTAssertEqual(TaskDraft.bullets(from: "2026 prices are shown"), ["2026 prices are shown"],
                       "only a number followed by . or ) is a list marker")
    }

    func testBodyIsTheDescriptionThenDoneWhen() {
        let draft = TaskDraft(title: "T", bulletsText: "- a\n- b", description: "  Why it matters.  ")
        XCTAssertEqual(draft.body, "Why it matters.\n\n## Done when\n- a\n- b")
    }

    func testBodyOmitsAnEmptyPart() {
        XCTAssertEqual(TaskDraft(title: "T", bulletsText: "a", description: "").body, "## Done when\n- a")
        XCTAssertEqual(TaskDraft(title: "T", bulletsText: "", description: "only prose").body, "only prose")
        XCTAssertEqual(TaskDraft(title: "T").body, "")
    }

    // MARK: - Destination

    func testASlugMeansGitHub() {
        XCTAssertEqual(TaskDestination.resolve(slug: "o/r", trackerUnavailable: nil), .github(slug: "o/r"))
        XCTAssertEqual(TaskDestination.resolve(slug: "o/r", trackerUnavailable: nil).label, "→ GitHub issue in o/r")
    }

    func testNoSlugIsLocalAndSaysWhy() {
        let destination = TaskDestination.resolve(slug: nil, trackerUnavailable: "not signed in")
        XCTAssertEqual(destination, .local(reason: "not signed in"))
        XCTAssertEqual(destination.label, "→ docs/backlog (not signed in)")
        XCTAssertEqual(TaskDestination.resolve(slug: nil, trackerUnavailable: nil), .local(reason: "no GitHub remote"))
    }

    // MARK: - Duplicate search

    func testKeywordsAreTheThreeLongestDistinctWords() {
        XCTAssertEqual(DuplicateSearch.keywords("Add a CI lane for the skill scripts, the scripts"),
                       ["scripts", "skill", "lane"])
    }

    func testKeywordsReadArabic() {
        XCTAssertEqual(DuplicateSearch.keywords("التحقق من آية وحديث").first, "التحقق")
    }

    func testNoKeywordsMeansNoSearch() {
        XCTAssertNil(DuplicateSearch.arguments(slug: "o/r", title: "do it"))
    }

    func testSearchArgumentsNameTheRepoAndAskForOpenIssues() {
        XCTAssertEqual(DuplicateSearch.arguments(slug: "o/r", title: "citations verified"),
                       ["issue", "list", "--repo", "o/r", "--state", "open", "--limit", "5",
                        "--search", "citations verified in:title,body", "--json", "number,title"])
    }

    func testParseReadsGhJsonAndFailsSoft() {
        XCTAssertEqual(DuplicateSearch.parse(#"[{"number":700,"title":"Citations"}]"#),
                       [DuplicateCandidate(number: 700, title: "Citations")])
        XCTAssertEqual(DuplicateSearch.parse("not json"), [])
    }

    func testLocalMatchesSharedKeywordsAndSkipsFiledAndDone() {
        func item(_ id: String, _ title: String, issue: Int? = nil, status: String? = nil) -> BacklogItem {
            BacklogItem(id: id, key: "", title: title, issue: issue, status: status, body: "", path: "/tmp/\(id).md")
        }
        let items = [item("a", "Verify hadith citations against a source"),
                     item("b", "Verify hadith citations", issue: 12),
                     item("c", "Hadith citations are verified", status: "done"),
                     item("d", "Something else entirely")]
        XCTAssertEqual(DuplicateSearch.local(items, title: "Hadith citations get verified").map(\.localEntry), ["a"])
    }

    // MARK: - Issue create

    func testCreateArgumentsCarryTheBodyAndAnOptionalMilestone() {
        let draft = TaskDraft(title: "  Title  ", bulletsText: "a", description: "")
        XCTAssertEqual(IssueCreate.arguments(slug: "o/r", draft: draft, milestone: nil),
                       ["issue", "create", "--repo", "o/r", "--title", "Title", "--body", "## Done when\n- a"])
        XCTAssertEqual(IssueCreate.arguments(slug: "o/r", draft: draft, milestone: " M ").suffix(2), ["--milestone", "M"])
        XCTAssertFalse(IssueCreate.arguments(slug: "o/r", draft: draft, milestone: "  ").contains("--milestone"))
    }

    func testTheNumberIsReadFromGhsUrlAndNeverGuessed() {
        XCTAssertEqual(IssueCreate.number(fromOutput: "https://github.com/o/r/issues/812\n"), 812)
        XCTAssertNil(IssueCreate.number(fromOutput: "created"))
    }
}

// MARK: - The model files where the tracker is

private struct TrackerSource: ProjectDataSource {
    let root: String
    let slug: String?
    func load() async throws -> ProjectSnapshot {
        let items = LocalBacklog.read(projectPath: root)
        let stages = BoardStages.read(projectRoot: URL(fileURLWithPath: root, isDirectory: true)).stages
        var snapshot = ProjectSnapshot(project: ProjectInfo(name: "p", displayPath: root, branch: "main"), isDemo: false,
                                       board: .available(BoardBuilder.build(BoardInput(localBacklog: items, stages: stages))),
                                       boardNote: "", findings: .available(FindingsReport(runs: [], findings: [])),
                                       roadmap: .unavailable("n/a"), connections: [], connectionsNote: "",
                                       capabilities: CapabilityMatrix(providers: [], rows: [], note: ""),
                                       insights: .unavailable("none"), slug: slug, localBacklog: items,
                                       filedBacklogKeys: LocalBacklog.filedKeys(projectPath: root), repositoryRoot: root)
        snapshot.trackerUnavailable = slug == nil ? "not signed in" : nil
        return snapshot
    }
}

@MainActor
final class AddTaskDestinationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("add-task-0045-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func model(slug: String?, runner: FakeRunner) async -> ProjectWindowModel {
        let model = ProjectWindowModel(ref: .local(path: root.path), source: TrackerSource(root: root.path, slug: slug),
                                       insightsDelay: .zero, runner: runner)
        await model.load()
        return model
    }

    private var backlogFiles: [String] {
        let directory = root.appendingPathComponent(LocalBacklog.folder, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".md") }
    }

    private let draft = TaskDraft(title: "Citations are verified", bulletsText: "- a fabricated one is caught", description: "Why.")

    func testWithATrackerTheTaskBecomesAnIssueAndNoFileIsWritten() async {
        let runner = FakeRunner()
        let create = (["gh"] + IssueCreate.arguments(slug: "o/r", draft: draft, milestone: "Certificate")).joined(separator: " ")
        runner.script(create, .ok("https://github.com/o/r/issues/812\n"))
        let model = await model(slug: "o/r", runner: runner)

        let id = await model.addTask(draft, milestone: "Certificate", column: .backlog)

        XCTAssertEqual(id, "812")
        XCTAssertTrue(runner.keys.contains(create), "one gh issue create, with the milestone")
        XCTAssertEqual(backlogFiles, [], "a reachable tracker is filed into, not docs/backlog/")
        XCTAssertNil(model.writeFailure)
    }

    func testAFailedCreateSaysSoAndFilesNothingElsewhere() async {
        let runner = FakeRunner()
        let create = (["gh"] + IssueCreate.arguments(slug: "o/r", draft: draft, milestone: nil)).joined(separator: " ")
        runner.script(create, .failed(stderr: "could not add to milestone"))
        let model = await model(slug: "o/r", runner: runner)

        let id = await model.addTask(draft, milestone: nil, column: .backlog)

        XCTAssertNil(id)
        XCTAssertEqual(backlogFiles, [], "a failed GitHub write never falls back to a silent local file")
        XCTAssertTrue(model.writeFailure?.message.contains("could not add to milestone") ?? false)
    }

    func testAnUnnumberedCreateIsNotGuessed() async {
        let runner = FakeRunner()
        let create = (["gh"] + IssueCreate.arguments(slug: "o/r", draft: draft, milestone: nil)).joined(separator: " ")
        runner.script(create, .ok("done"))
        let model = await model(slug: "o/r", runner: runner)

        let id = await model.addTask(draft, milestone: nil, column: .backlog)

        XCTAssertNil(id)
        XCTAssertNotNil(model.writeFailure, "the issue exists, and the developer is told to find it on GitHub")
    }

    func testWithoutATrackerItIsALocalFileCarryingDoneWhen() async throws {
        let model = await model(slug: nil, runner: FakeRunner())
        XCTAssertEqual(model.addTaskDestination, .local(reason: "not signed in"))

        let id = await model.addTask(draft, milestone: "ignored", column: .readyForDev)

        let entry = try XCTUnwrap(LocalBacklog.read(projectPath: root.path).first)
        XCTAssertEqual(id, DeskTask.localPrefix + entry.id)
        let text = try String(contentsOfFile: root.appendingPathComponent("\(LocalBacklog.folder)/\(entry.id).md").path, encoding: .utf8)
        XCTAssertTrue(text.contains("## Done when\n- a fabricated one is caught"))
        XCTAssertEqual(model.task(try XCTUnwrap(id))?.column, .readyForDev)
    }

    func testDuplicatesSearchGitHubAndAFailedSearchIsNotEmpty() async {
        let runner = FakeRunner()
        let search = (["gh"] + (DuplicateSearch.arguments(slug: "o/r", title: draft.title) ?? [])).joined(separator: " ")
        runner.script(search, .ok(#"[{"number":700,"title":"Citations are model-asserted"}]"#))
        let found = await model(slug: "o/r", runner: runner).possibleDuplicates(for: draft.title)
        XCTAssertEqual(found?.map(\.number), [700])

        let failing = await model(slug: "o/r", runner: FakeRunner()).possibleDuplicates(for: draft.title)
        XCTAssertNil(failing, "an unscripted (failed) gh reads as a failed search, never as no duplicates")
    }
}

/// A session mid-turn is visible outside the app (install.sh's guard) through `.working`, 2026-09-19.
final class WorkingMarkerTests: XCTestCase {
    func testATurnMarksTheSessionWorkingAndItsEndClearsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent(AgentHooks.workingMarker)
        AgentHooks.markWorking(.turnStarted, in: dir)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), String(ProcessInfo.processInfo.processIdentifier))
        AgentHooks.markWorking(.bell, in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "a bell says nothing about a turn")
        AgentHooks.markWorking(.turnFinished, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        AgentHooks.markWorking(.turnStarted, in: dir)
        AgentHooks.markWorking(.question(nil), in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "waiting on a question is not working")
    }
}
