import Foundation
import XCTest
@testable import DeskCore

final class RunJournalTests: XCTestCase {
    private var root: URL!
    private var journal: RunJournal!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        journal = RunJournal(projectRoot: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Whole seconds: the file stores ISO dates, and a record read back is compared whole.
    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_757_800_000 + offset)
    }

    private func record(id: String, clean: Bool = false, lastSeen: TimeInterval = 0) -> JournalRecord {
        JournalRecord(id: id, kind: .backgroundRun, title: "Findings", agent: "Claude", directory: root.path,
                      startedAt: date(0), lastSeenAt: date(lastSeen), sessionID: "sess-9", door: "findings",
                      subject: "finding:12", permission: RunPermission.readOnly.rawValue,
                      mode: RunMode.standard.rawValue, stateLabel: "Running in the background",
                      logTail: ["· Read AGENTS.md", "Reading the door"], clean: clean)
    }

    private var runsDirectory: URL { root.appendingPathComponent(".devdesk/runs", isDirectory: true) }

    /// Every field has to survive the round trip: a record that loses its permission or its session id
    /// recovers into a run started under a grant nobody chose, or into no resume at all.
    func testARecordRoundTripsWithEveryFieldIntact() throws {
        let written = record(id: "job:findings:ab12cd34")
        journal.write(written)
        XCTAssertEqual(journal.all(), [written])
        XCTAssertEqual(journal.recover(), [written])
    }

    func testATerminalSessionKeepsWhatItWas() throws {
        let session = JournalRecord(id: "task-41", kind: .terminalSession, title: "Fix the board",
                                    agent: "Codex", directory: root.path, stateLabel: "Running",
                                    purpose: "agent", branch: "feat/board", folderPath: "/tmp/wt/board")
        journal.write(session)
        let read = try XCTUnwrap(journal.all().first)
        XCTAssertEqual(read.kind, .terminalSession)
        XCTAssertEqual(read.purpose, "agent")
        XCTAssertEqual(read.branch, "feat/board")
        XCTAssertEqual(read.folderPath, "/tmp/wt/board")
    }

    /// The journal is rewritten on every state change, so the same id must stay one file — the alternative is
    /// a directory that grows a record per line a run writes.
    func testWritingTheSameIdOverwritesRatherThanAccumulates() throws {
        journal.write(record(id: "job:findings:ab12cd34"))
        var second = record(id: "job:findings:ab12cd34", lastSeen: 30)
        second.stateLabel = "Waiting for your answer"
        journal.write(second)
        let files = try FileManager.default.contentsOfDirectory(at: runsDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(journal.all(), [second])
    }

    func testRecoverReturnsOnlyUncleanRecordsNewestFirst() {
        journal.write(record(id: "old", lastSeen: 10))
        journal.write(record(id: "new", lastSeen: 90))
        journal.write(record(id: "quit-gracefully", clean: true, lastSeen: 200))
        XCTAssertEqual(journal.recover().map(\.id), ["new", "old"])
        XCTAssertEqual(journal.all().map(\.id), ["quit-gracefully", "new", "old"])
    }

    func testClearRemovesTheRecordAndIsSafeWhenAbsent() {
        journal.write(record(id: "job:findings:ab12cd34"))
        journal.clear(id: "job:findings:ab12cd34")
        XCTAssertTrue(journal.all().isEmpty)
        XCTAssertTrue(journal.recover().isEmpty)
        journal.clear(id: "never-written")
        XCTAssertTrue(journal.all().isEmpty)
    }

    /// A graceful quit does not delete the record — it stops it claiming to be a crash.
    func testMarkCleanLeavesTheRecordButTakesItOutOfRecovery() throws {
        journal.write(record(id: "job:findings:ab12cd34"))
        journal.markClean(id: "job:findings:ab12cd34")
        XCTAssertTrue(journal.recover().isEmpty)
        XCTAssertEqual(journal.all().map(\.id), ["job:findings:ab12cd34"])
        XCTAssertEqual(journal.all().first?.clean, true)
        journal.markClean(id: "never-written")
    }

    /// The filename is sanitised because an id holds `:` and can hold `/`; the id itself must not be, because
    /// it is what a resume, a clear and the live registry all name the run by.
    func testAnIdWithPathCharactersKeepsItsRealIdInside() throws {
        let awkward = "job:findings/nested:ab 12"
        journal.write(record(id: awkward))
        let files = try FileManager.default.contentsOfDirectory(at: runsDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["job-findings-nested-ab-12.json"])
        XCTAssertEqual(journal.recover().map(\.id), [awkward])
        journal.clear(id: awkward)
        XCTAssertTrue(journal.all().isEmpty)
    }

    /// A truncated write, or somebody's stray file, must cost only itself.
    func testACorruptFileIsSkippedRatherThanBreakingRecovery() throws {
        journal.write(record(id: "good"))
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        try Data("{ not json at all".utf8).write(to: runsDirectory.appendingPathComponent("broken.json"))
        XCTAssertEqual(journal.recover().map(\.id), ["good"])
        XCTAssertEqual(journal.all().map(\.id), ["good"])
    }

    func testPurgeCleanTakesOnlyTheCleanRecords() {
        journal.write(record(id: "crashed"))
        journal.write(record(id: "quit-gracefully", clean: true))
        journal.purgeClean()
        XCTAssertEqual(journal.all().map(\.id), ["crashed"])
    }

    /// A journal in a folder nothing has created yet reads as empty rather than failing — the first launch in
    /// a project, and every project that has never run anything.
    func testAJournalWithNoDirectoryYetIsSimplyEmpty() {
        let fresh = RunJournal(projectRoot: root.appendingPathComponent("not-created"))
        XCTAssertTrue(fresh.all().isEmpty)
        XCTAssertTrue(fresh.recover().isEmpty)
        fresh.purgeClean()
    }

    /// The cap matches the live log's: a recovered row shows the end of a run, not its transcript.
    func testTheLogTailIsCappedAtTheLiveLogsLimit() {
        var long = record(id: "chatty")
        long.logTail = (0..<500).map { "line \($0)" }
        journal.write(JournalRecord(id: long.id, kind: .backgroundRun, title: long.title, agent: long.agent,
                                    directory: long.directory, stateLabel: long.stateLabel, logTail: long.logTail))
        let read = journal.all().first
        XCTAssertEqual(read?.logTail.count, BackgroundJob.logLimit)
        XCTAssertEqual(read?.logTail.last, "line 499")
    }
}
