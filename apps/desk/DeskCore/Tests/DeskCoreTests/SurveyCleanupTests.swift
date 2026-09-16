import XCTest
@testable import DeskCore

/// A cleanup that takes the current picture away is not a cleanup. These guard what it keeps.
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

    func testTheNewestReportIsNeverOlder() throws {
        let root = try makeReports(["2026-09-01.md", "2026-09-13.md", "2026-08-20.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SurveyCleanup.olderReports(in: root.path), ["2026-09-01.md", "2026-08-20.md"])
    }

    func testASingleReportIsLeftAlone() throws {
        let root = try makeReports(["2026-09-13.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SurveyCleanup.olderReports(in: root.path), [])
    }

    /// Only reports: a subfolder is somebody's own arrangement, and a dotfile is not a report.
    func testOnlyMarkdownFilesInTheFolderItselfCount() throws {
        let root = try makeReports(["2026-09-13.md", "2026-09-01.md", "notes.txt", ".DS_Store"])
        let nested = root.appendingPathComponent("\(SurveyCleanup.folder)/archive", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "# old".write(to: nested.appendingPathComponent("2025-01-01.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(SurveyCleanup.olderReports(in: root.path), ["2026-09-01.md"])
    }

    func testAProjectWithNoSurveyFolderHasNothingToClean() {
        XCTAssertEqual(SurveyCleanup.olderReports(in: "/tmp/definitely-not-a-project-\(UUID().uuidString)"), [])
    }

    func testResetOptionsAreEmptyOnlyWhenNothingWasAskedFor() {
        XCTAssertTrue(SurveyResetOptions(ignoredFindings: false, viewState: false, olderReports: false).isEmpty)
        XCTAssertFalse(SurveyResetOptions(ignoredFindings: false, viewState: false, olderReports: true).isEmpty)
    }

    func testClosingAnIssueIsSomethingToReset() {
        XCTAssertFalse(SurveyResetOptions(ignoredFindings: false, viewState: false, closeIssues: [12]).isEmpty)
    }

    /// Only an untouched issue is offered: started work is closed from its own card, never from a reset.
    func testOnlyUntouchedIssuesAreClosable() {
        XCTAssertEqual(FiledCardReset.of(column: .backlog, branch: nil, issue: 7), .closable(issue: 7))
        XCTAssertEqual(FiledCardReset.of(column: .queued, branch: nil, issue: 7), .closable(issue: 7))
        XCTAssertEqual(FiledCardReset.of(column: .readyForDev, branch: "feat/x", issue: 7), .started)
        XCTAssertEqual(FiledCardReset.of(column: .inProgress, branch: nil, issue: 7), .started)
        XCTAssertEqual(FiledCardReset.of(column: .review, branch: nil, issue: 7), .started)
        XCTAssertEqual(FiledCardReset.of(column: .done, branch: "feat/x", issue: 7), .done)
        XCTAssertEqual(FiledCardReset.of(column: .backlog, branch: nil, issue: nil), .localOnly)
    }
}
