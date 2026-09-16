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
    }
}
