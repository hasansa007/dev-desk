import XCTest
@testable import DeskCore

final class LocalBacklogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("backlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAnItemIsWrittenAndReadBack() throws {
        let path = try LocalBacklog.write(projectPath: root.path, key: "2026-08-31-C1",
                                          title: "Callback fetch returns 0 reminders, never 12",
                                          body: "mechanism: the loop only schedules three calls.",
                                          area: "Logic", source: "dev:findings run 2026-08-31")
        XCTAssertTrue(path.hasSuffix("docs/backlog/2026-08-31-c1-callback-fetch-returns-0-reminders-never-12.md"), path)

        let items = LocalBacklog.read(projectPath: root.path)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].key, "2026-08-31-C1")
        XCTAssertEqual(items[0].title, "Callback fetch returns 0 reminders, never 12")
        XCTAssertEqual(items[0].area, "Logic")
        XCTAssertEqual(items[0].source, "dev:findings run 2026-08-31")
        XCTAssertNil(items[0].issue, "nothing has been filed to a tracker yet")
        // Unrated, the same as an issue nobody has rated (ADR 0020).
        XCTAssertNil(items[0].impact)
        XCTAssertTrue(items[0].body.contains("mechanism"), items[0].body)
        XCTAssertFalse(items[0].body.hasPrefix("# "), "the title is the card's header, not the body's first line")
    }

    /// What a findings run writes: the labels an issue would carry, a priority line, and its place in the run.
    func testLabelsPriorityAndOrderAreReadSoALocalCardFiltersLikeAnIssue() {
        let text = "---\nkey: C1\ntitle: Phone search\npriority: P1\nlabels: bug, search, security, impact:high\norder: 4 of 6 · G2 2 of 3\n---\n\nbody"
        let item = LocalBacklog.parse(text, id: "c1", path: "/p/docs/backlog/c1.md")
        XCTAssertEqual(item.labels, ["bug", "search", "security", "impact:high", "P1"])
        XCTAssertEqual(item.order, 4)
        XCTAssertNil(LocalBacklog.parse("---\nkey: C2\ntitle: t\n---\n", id: "c2", path: "/p/c2.md").order)
    }

    /// A card with none of them reads as an unlabelled issue does: no priority, a Feature, no tags.
    func testACardWithNoLabelsOrPriorityHasNone() {
        let item = LocalBacklog.parse("---\nkey: C2\ntitle: t\npriority: urgent\n---\n", id: "c2", path: "/p/c2.md")
        XCTAssertEqual(item.labels, [], "a priority outside P0–P3 is not a priority label")
    }

    /// The CallApp cards (2026-09-16) say `type: bug` and no `labels:` line; without folding the type in they read
    /// as Features under the Type filter.
    func testTypeBugOrEpicJoinsTheLabels() {
        let bug = LocalBacklog.parse("---\nkey: C1\ntitle: t\ntype: bug\npriority: P2\nissue: null\n---\n", id: "c1", path: "/p/c1.md")
        XCTAssertEqual(bug.labels, ["bug", "P2"])
        XCTAssertNil(bug.issue, "`null` is no issue")
        let feature = LocalBacklog.parse("---\nkey: C3\ntitle: t\ntype: feature\nlabels: bug\n---\n", id: "c3", path: "/p/c3.md")
        XCTAssertEqual(feature.labels, ["bug"], "only bug and epic change the kind, and a label already there is not repeated")
    }

    /// The app writes the same two lines a findings run does, and reads them back as the card's labels.
    func testLabelsAndPriorityAreWrittenAndReadBack() throws {
        let path = try LocalBacklog.write(projectPath: root.path, key: "C1", title: "Phone search", body: "b",
                                          labels: ["bug", "search", "P1"], priority: "P1")
        let text = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(text.contains("\npriority: P1\n"), text)
        XCTAssertTrue(text.contains("\nlabels: bug, search\n"), "the priority has its own line, not a second copy: \(text)")
        XCTAssertEqual(LocalBacklog.read(projectPath: root.path).first?.labels, ["bug", "search", "P1"])
        let bare = try String(contentsOfFile: LocalBacklog.write(projectPath: root.path, key: "C2", title: "Bare", body: "b"), encoding: .utf8)
        XCTAssertFalse(bare.contains("labels:") || bare.contains("priority:"), "nothing is written for a card with neither")
    }

    /// File on GitHub asks for the card's labels as real labels, and for a missing one to be offered (ADR 0020).
    func testPromotionAsksForTheCardsLabels() {
        let item = BacklogItem(id: "c1", key: "C1", title: "Phone search", labels: ["bug", "P1"], body: "", path: "/p/docs/backlog/c1.md")
        let request = LocalBacklog.promotionRequest(for: item)
        XCTAssertTrue(request.hasPrefix("Phone search. The full description is in docs/backlog/c1.md"), request)
        XCTAssertTrue(request.contains("labels: bug, P1"), request)
        XCTAssertTrue(request.contains("never create"), request)
        let unlabelled = LocalBacklog.promotionRequest(for: BacklogItem(id: "c2", key: "", title: "T", body: "", path: "/p/c2.md"))
        XCTAssertFalse(unlabelled.contains("labels"), unlabelled)
    }

    /// A second press of the same button must not replace what the first one wrote.
    func testFilingTheSameItemTwiceKeepsTheFirst() throws {
        let first = try LocalBacklog.write(projectPath: root.path, key: "C1", title: "Same", body: "original")
        let second = try LocalBacklog.write(projectPath: root.path, key: "C1", title: "Same", body: "replacement")
        XCTAssertEqual(first, second)
        XCTAssertEqual(LocalBacklog.read(projectPath: root.path).count, 1)
        XCTAssertTrue(LocalBacklog.read(projectPath: root.path)[0].body.contains("original"))
        XCTAssertTrue(LocalBacklog.contains(key: "C1", projectPath: root.path))
        XCTAssertFalse(LocalBacklog.contains(key: "C2", projectPath: root.path))
    }

    func testPromotingRecordsTheIssueItBecame() throws {
        let path = try LocalBacklog.write(projectPath: root.path, key: "C1", title: "Needs a number", body: "body")
        try LocalBacklog.recordIssue(87, atPath: path, projectPath: root.path)
        XCTAssertEqual(LocalBacklog.read(projectPath: root.path)[0].issue, 87)
        // Read back through the same parser a second time: recording must not corrupt the header.
        XCTAssertEqual(LocalBacklog.read(projectPath: root.path)[0].title, "Needs a number")
    }

    func testAnIssueNumberIsReadHoweverItWasWritten() {
        XCTAssertEqual(LocalBacklog.issueNumber("#123"), 123)
        XCTAssertEqual(LocalBacklog.issueNumber("123"), 123)
        XCTAssertEqual(LocalBacklog.issueNumber("https://github.com/acme/app/issues/123"), 123)
        XCTAssertNil(LocalBacklog.issueNumber("none"))
    }

    /// A title is a person's text: it must not be able to name a file outside the folder.
    func testATitleCannotEscapeTheFolder() throws {
        let path = try LocalBacklog.write(projectPath: root.path, key: "../../etc", title: "../../../passwd", body: "x")
        XCTAssertTrue(path.contains("/docs/backlog/"), path)
        XCTAssertFalse(path.contains(".."), path)
    }

    func testAMissingFolderIsAnEmptyBacklogRatherThanAFailure() {
        XCTAssertEqual(LocalBacklog.read(projectPath: root.path), [])
    }

    // MARK: - Promotion (ADR 0027)

    /// A URL into this repository is unambiguous; prose mentions other issues.
    func testTheIssueARunCreatedIsReadFromItsURLFirst() {
        let text = "Related to #42. Filed https://github.com/acme/app/issues/87 with labels bug, impact: high."
        XCTAssertEqual(LocalBacklog.issueNumber(inRunResult: text, slug: "acme/app"), 87)
    }

    func testWithoutAURLTheLastNumberIsTheOneItFiled() {
        XCTAssertEqual(LocalBacklog.issueNumber(inRunResult: "Related to #42; created #87.", slug: "acme/app"), 87)
    }

    /// A URL into a DIFFERENT repository is not the issue this run filed here.
    func testAnotherRepositorysURLIsNotMistakenForThisOne() {
        let text = "See https://github.com/other/repo/issues/5 — filed #12"
        XCTAssertEqual(LocalBacklog.issueNumber(inRunResult: text, slug: "acme/app"), 12)
    }

    func testNoNumberIsNilRatherThanAGuess() {
        XCTAssertNil(LocalBacklog.issueNumber(inRunResult: "I could not reach GitHub.", slug: "acme/app"))
    }

    /// After promotion GitHub owns it: the file leaves the folder the board reads, and is kept as history.
    func testMarkingFiledMovesTheEntryOutOfTheBacklog() throws {
        let path = try LocalBacklog.write(projectPath: root.path, key: "C1", title: "Promote me", body: "body")
        try LocalBacklog.markFiled(87, atPath: path, projectPath: root.path)

        XCTAssertEqual(LocalBacklog.read(projectPath: root.path), [], "no second editable copy on the board")
        XCTAssertEqual(LocalBacklog.filedKeys(projectPath: root.path), ["C1"])
        let filed = root.appendingPathComponent("docs/backlog/filed/c1-promote-me.md").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: filed))
        XCTAssertTrue(try String(contentsOfFile: filed, encoding: .utf8).contains("issue: #87"))
    }

    func testRemovingOnlyTouchesTheBacklogFolder() throws {
        let outside = root.appendingPathComponent("README.md")
        try Data("keep".utf8).write(to: outside)
        try LocalBacklog.remove(atPath: outside.path, projectPath: root.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "a path outside docs/backlog/ is refused")
    }

    /// A draft written to disk reads as prose, not as the app's escaped rendering of it.
    func testAFindingsDraftIsReadableAsAFile() {
        let report = "## CONFIRMED (1)\n- **Holds @ObservedObject** · `MainScreen.swift:39` · mechanism: it is re-created [every] push\n"
        let finding = FindingsReportParser.parse(report, runID: "2026-08-31")[0]
        let draft = finding.backlogDraft
        XCTAssertEqual(draft.key, finding.id)
        XCTAssertEqual(draft.title, "Holds @ObservedObject")
        XCTAssertTrue(draft.body.contains("mechanism: it is re-created [every] push"), draft.body)
        XCTAssertFalse(draft.body.contains("^[@]"), draft.body)
        XCTAssertTrue(draft.body.contains("- `MainScreen.swift:39`"), draft.body)
        XCTAssertEqual(draft.area, "UI")
        var defect = finding; defect.kind = .defect
        XCTAssertEqual(defect.backlogDraft.labels, ["bug"], "a defect is filed as the bug it is")
        var architecture = finding; architecture.kind = .architecture
        XCTAssertEqual(architecture.backlogDraft.labels, [])
    }
}
