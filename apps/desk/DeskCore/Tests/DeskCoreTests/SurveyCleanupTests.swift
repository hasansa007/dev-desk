import XCTest
@testable import DeskCore

/// A reset clears the findings and what they filed, and never work in progress (ADR 0041).
final class SurveyCleanupTests: XCTestCase {
    private func makeReports(_ names: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("survey-cleanup-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(SurveyCleanup.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try "# report".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return root
    }

    func testEveryReportIsListedNewestFirst() throws {
        let root = try makeReports(["2026-09-01.md", "2026-09-13.md", "2026-08-20.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SurveyCleanup.reports(in: root.path), ["2026-09-13.md", "2026-09-01.md", "2026-08-20.md"])
    }

    func testTrashingReportsTakesTheNewestToo() throws {
        let root = try makeReports(["2026-09-13.md", "2026-09-01.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try SurveyCleanup.trashReports(in: root.path), 2)
        XCTAssertEqual(SurveyCleanup.reports(in: root.path), [])
    }

    /// Only reports: a subfolder is somebody's own arrangement, and a dotfile is not a report.
    func testOnlyMarkdownFilesInTheFolderItselfCount() throws {
        let root = try makeReports(["2026-09-13.md", "notes.txt", ".DS_Store"])
        let nested = root.appendingPathComponent("\(SurveyCleanup.folder)/archive", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "# old".write(to: nested.appendingPathComponent("2025-01-01.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SurveyCleanup.reports(in: root.path), ["2026-09-13.md"])
    }

    func testAProjectWithNoSurveyFolderHasNothingToClean() {
        XCTAssertEqual(SurveyCleanup.reports(in: "/tmp/definitely-not-a-project-\(UUID().uuidString)"), [])
    }

    func testResetOptionsAreEmptyOnlyWhenNothingWasAskedFor() {
        XCTAssertTrue(SurveyResetOptions(ignoredFindings: false, viewState: false).isEmpty)
        XCTAssertFalse(SurveyResetOptions(ignoredFindings: false, viewState: false, reports: true).isEmpty)
        XCTAssertFalse(SurveyResetOptions(ignoredFindings: false, viewState: false, closeIssues: [12]).isEmpty)
        XCTAssertFalse(SurveyResetOptions(ignoredFindings: false, viewState: false, trashBacklogIDs: ["x"]).isEmpty)
    }

    func testAFiledCardGoesUnlessItIsInProgress() {
        XCTAssertEqual(FiledCardReset.of(column: .backlog, branch: nil, issue: 7, localBacklogID: nil), .closable(issue: 7))
        XCTAssertEqual(FiledCardReset.of(column: .queued, branch: nil, issue: 7, localBacklogID: nil), .closable(issue: 7))
        XCTAssertEqual(FiledCardReset.of(column: .backlog, branch: nil, issue: nil, localBacklogID: "a"), .trashable(entry: "a"))
        XCTAssertEqual(FiledCardReset.of(column: .done, branch: "feat/x", issue: nil, localBacklogID: "a"), .trashable(entry: "a"))
        XCTAssertEqual(FiledCardReset.of(column: .done, branch: "feat/x", issue: 7, localBacklogID: nil), .done)
        XCTAssertEqual(FiledCardReset.of(column: .readyForDev, branch: "feat/x", issue: 7, localBacklogID: nil), .inProgress)
        XCTAssertEqual(FiledCardReset.of(column: .inProgress, branch: nil, issue: nil, localBacklogID: "a"), .inProgress)
        XCTAssertEqual(FiledCardReset.of(column: .review, branch: nil, issue: 7, localBacklogID: nil), .inProgress)
    }
}
