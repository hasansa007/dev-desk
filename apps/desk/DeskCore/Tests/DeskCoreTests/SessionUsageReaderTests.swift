import Foundation
import XCTest
@testable import DeskCore

/// Everything here runs against a temporary home holding recorded lines. No agent is started: the reader's
/// whole job is to find and parse a file, and a test that needed a live session would never be run twice.
final class SessionUsageReaderTests: XCTestCase {
    private var home: URL!
    private var project: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("usage-home-\(UUID().uuidString)")
        project = FileManager.default.temporaryDirectory.appendingPathComponent("usage-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: project)
    }

    private var directory: String { project.standardizedFileURL.path }

    // MARK: - Claude

    /// Verified on this machine: cwd `/Users/hasan/.devdesk/wt/x` is the directory `-Users-hasan--devdesk-wt-x`.
    /// The doubled dash is the dot of the hidden directory following the slash, not a separator to collapse.
    func testTheClaudeSlugTurnsEverySlashAndDotIntoADash() {
        XCTAssertEqual(SessionUsageReader.claudeSlug("/Users/hasan/.devdesk/wt/studyhub-deploy-auto-claude-004"),
                       "-Users-hasan--devdesk-wt-studyhub-deploy-auto-claude-004")
        XCTAssertEqual(SessionUsageReader.claudeSlug("/Users/hasan/Developer/dev-skill"), "-Users-hasan-Developer-dev-skill")
    }

    func testClaudeReadsTheNewestSessionInItsProjectDirectory() throws {
        try writeClaude("older.jsonl", used: 500, modified: Date().addingTimeInterval(-600))
        try writeClaude("newer.jsonl", used: 1_200, modified: Date())
        let usage = try XCTUnwrap(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path))
        XCTAssertEqual(usage.used, 1_200, "the session running now is the one written to last")
        XCTAssertNil(usage.percent, "Claude states no window, so there is nothing to divide by")
    }

    /// The last reading in the file is the current one; the ones above it are turns that have already passed.
    func testClaudeTakesTheLastReadingInTheFile() throws {
        let lines = [Self.claudeLine(used: 100), Self.claudeLine(used: 900), Self.claudeLine(used: 4_000)]
        try write(claudeDirectory().appendingPathComponent("s.jsonl"), lines.joined(separator: "\n") + "\n")
        XCTAssertEqual(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path)?.used, 4_000)
    }

    // MARK: - Codex

    /// Codex names its files by date and says nothing about the folder in the name, so the `session_meta` line
    /// is the only way to tell this repository's session from another's.
    func testCodexFindsTheNewestRolloutWhoseSessionMetaMatchesTheFolder() throws {
        try writeCodex("2026/09/13", "rollout-2026-09-13T10-00-00-aaa.jsonl", cwd: "/somewhere/else",
                       used: 111, modified: Date())
        try writeCodex("2026/09/12", "rollout-2026-09-12T10-00-00-bbb.jsonl", cwd: directory,
                       used: 222, modified: Date().addingTimeInterval(-3_600))
        let usage = try XCTUnwrap(SessionUsageReader.usage(agent: .codex, directory: directory, home: home.path))
        XCTAssertEqual(usage.used, 222, "another folder's newer session is not this one's meter")
        XCTAssertEqual(usage.window, 258_400)
        XCTAssertEqual(usage.percent, 0)
    }

    func testCodexPrefersTheNewestOfTwoSessionsInTheSameFolder() throws {
        try writeCodex("2026/09/12", "rollout-2026-09-12T10-00-00-old.jsonl", cwd: directory,
                       used: 10_000, modified: Date().addingTimeInterval(-7_200))
        try writeCodex("2026/09/13", "rollout-2026-09-13T10-00-00-new.jsonl", cwd: directory,
                       used: 20_000, modified: Date())
        XCTAssertEqual(SessionUsageReader.usage(agent: .codex, directory: directory, home: home.path)?.used, 20_000)
    }

    // MARK: - Nothing to read

    /// A home where the agent has never run, an empty log and a file in some other format all mean the same:
    /// no meter. None of them is a crash, and none of them is a guessed number.
    func testAMissingDirectoryIsNoMeter() {
        XCTAssertNil(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path))
        XCTAssertNil(SessionUsageReader.usage(agent: .codex, directory: directory, home: home.path))
    }

    func testAnEmptyLogIsNoMeter() throws {
        try write(claudeDirectory().appendingPathComponent("s.jsonl"), "")
        XCTAssertNil(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path))
    }

    func testAnUnparsableLogIsNoMeter() throws {
        try write(claudeDirectory().appendingPathComponent("s.jsonl"), "not json\n{ half a line\n<html></html>\n")
        XCTAssertNil(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path))
    }

    func testAFolderWithNoMatchingCodexSessionIsNoMeter() throws {
        try writeCodex("2026/09/13", "rollout-2026-09-13T10-00-00-aaa.jsonl", cwd: "/somewhere/else",
                       used: 111, modified: Date())
        XCTAssertNil(SessionUsageReader.usage(agent: .codex, directory: directory, home: home.path))
    }

    // MARK: - The tail cap

    /// A real session's transcript reaches many megabytes, and this is polled every few seconds while an agent
    /// works. Only the end is read — and the newest reading, which is what the meter shows, is in the end.
    func testAFileLargerThanTheCapStillYieldsItsLastReading() throws {
        let filler = String(repeating: "x", count: 4_000)
        var text = ""
        while text.utf8.count < SessionUsageReader.tailBytes * 2 {
            text += "{\"type\":\"user\",\"note\":\"\(filler)\"}\n"
        }
        let beyondTheTail = text.utf8.count
        text += Self.claudeLine(used: 77_777) + "\n"
        try write(claudeDirectory().appendingPathComponent("s.jsonl"), text)
        XCTAssertGreaterThan(beyondTheTail, SessionUsageReader.tailBytes, "the fixture has to outrun the cap to test it")
        XCTAssertEqual(SessionUsageReader.usage(agent: .claude, directory: directory, home: home.path)?.used, 77_777)
    }

    func testOnlyTheTailIsRead() throws {
        let url = try claudeDirectory().appendingPathComponent("s.jsonl")
        try write(url, String(repeating: "a", count: 300_000))
        let text = try XCTUnwrap(SessionUsageReader.read(url, maxBytes: SessionUsageReader.tailBytes, fromEnd: true))
        XCTAssertEqual(text.utf8.count, SessionUsageReader.tailBytes)
    }

    // MARK: - Fixtures

    private static func claudeLine(used: Int) -> String {
        // The three input fields are summed, so the fixture splits the number the way a real turn does.
        #"{"type":"assistant","cwd":"/repo","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":8,"cache_read_input_tokens":"# + String(used - 10) + #","output_tokens":614}}}"#
    }

    private static func codexLines(cwd: String, used: Int) -> String {
        let meta = #"{"timestamp":"2026-09-13T20:34:52.120Z","type":"session_meta","payload":{"session_id":"01a0","cwd":"# + "\"\(cwd)\"" + #"}}"#
        let count = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"total_tokens":"# + String(used) + #"},"model_context_window":258400}}}"#
        return meta + "\n" + count + "\n"
    }

    private func claudeDirectory() throws -> URL {
        let url = home.appendingPathComponent(".claude/projects/\(SessionUsageReader.claudeSlug(directory))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeClaude(_ name: String, used: Int, modified: Date) throws {
        let url = try claudeDirectory().appendingPathComponent(name)
        try write(url, Self.claudeLine(used: used) + "\n", modified: modified)
    }

    private func writeCodex(_ day: String, _ name: String, cwd: String, used: Int, modified: Date) throws {
        let directory = home.appendingPathComponent(".codex/sessions/\(day)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(directory.appendingPathComponent(name), Self.codexLines(cwd: cwd, used: used), modified: modified)
    }

    private func write(_ url: URL, _ text: String, modified: Date? = nil) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }
}
