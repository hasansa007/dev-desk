import XCTest
@testable import DeskCore

final class AgentHooksTests: XCTestCase {
    /// The hooks go right after the executable, so a prompt placed after `-p` or at the end keeps its place.
    func testHooksAreAddedAfterTheExecutableOnly() {
        XCTAssertEqual(AgentHooks.inject(into: ["claude", "the prompt"]), ["claude", "--settings", AgentHooks.claudeSettings, "the prompt"])
        XCTAssertEqual(AgentHooks.inject(into: ["codex", "p"]), ["codex", "-c", AgentHooks.codexNotify, "p"])
        XCTAssertEqual(AgentHooks.inject(into: ["opencode", "--prompt", "p"]), ["opencode", "--prompt", "p"])
        XCTAssertEqual(AgentHooks.inject(into: [String]()), [])
    }

    func testATypedLineGetsTheHooksQuoted() {
        let line = AgentHooks.inject(into: "claude 'read it'")
        XCTAssertTrue(line.hasPrefix("claude --settings '"))
        XCTAssertTrue(line.hasSuffix(" 'read it'"))
        XCTAssertEqual(AgentHooks.inject(into: "claudette x"), "claudette x")
        XCTAssertEqual(AgentHooks.inject(into: "gemini -i 'x'"), "gemini -i 'x'")
    }

    /// Claude's settings are JSON with Notification, Stop and UserPromptSubmit hooks; Codex's TOML literal carries no quote that would end it.
    func testTheHookPayloadsAreWellFormed() throws {
        let object = try JSONSerialization.jsonObject(with: Data(AgentHooks.claudeSettings.utf8)) as? [String: Any]
        let hooks = try XCTUnwrap(object?["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Notification", "Stop", "UserPromptSubmit"])
        XCTAssertFalse(AgentHooks.script(event: "turn", payload: #"printf %s "$1""#).contains("'"))
        XCTAssertTrue(AgentHooks.codexNotify.hasPrefix("notify=['sh','-c','"))
    }

    /// The hook script really writes the event where the app looks, and stays silent outside Dev Desk.
    func testTheScriptWritesOneCompleteEventFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", AgentHooks.script(event: "question", payload: "cat")]
        process.environment = [AgentHooks.eventDirectoryVariable: dir.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"message":"Claude needs your permission to use Bash"}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        let name = try XCTUnwrap(files.first)
        let event = AgentHooks.event(fileName: name, contents: try Data(contentsOf: dir.appendingPathComponent(name)))
        XCTAssertEqual(event, .question("Claude needs your permission to use Bash"))
    }

    func testEventFilesAreRead() {
        XCTAssertEqual(AgentHooks.event(fileName: "turn.ab12", contents: Data()), .turnFinished)
        XCTAssertEqual(AgentHooks.event(fileName: "prompt.ab12", contents: Data()), .turnStarted)
        XCTAssertEqual(AgentHooks.event(fileName: "question.x", contents: Data("nope".utf8)), .question(nil))
        XCTAssertNil(AgentHooks.event(fileName: "question.y", contents: Data(#"{"message":"Claude is waiting for your input"}"#.utf8)),
                     "the idle reminder repeats the finished turn")
        XCTAssertNil(AgentHooks.event(fileName: ".event.x", contents: Data()))
        XCTAssertNil(AgentHooks.event(fileName: "other.x", contents: Data()))
    }

    /// A question is unfinished work: the marker outlives the turn that asked it, and the next turn clears it.
    func testAQuestionLeavesTheAskingMarkerUntilTheNextTurn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        AgentHooks.markWorking(.turnStarted, in: directory)
        XCTAssertTrue(exists(AgentHooks.workingMarker))
        AgentHooks.markWorking(.question("approve?"), in: directory)
        XCTAssertFalse(exists(AgentHooks.workingMarker), "it is not working while it waits")
        XCTAssertTrue(exists(AgentHooks.askingMarker))
        AgentHooks.markWorking(.turnStarted, in: directory)
        XCTAssertFalse(exists(AgentHooks.askingMarker), "answering is what starts the next turn")
        AgentHooks.markWorking(.exited(0), in: directory)
        XCTAssertFalse(exists(AgentHooks.workingMarker))
    }

    /// Codex has one hook, for the end of a turn, and asks in that same breath: its finished turn waits for you,
    /// so it leaves the marker an install refuses on.
    func testACodexTurnEndCountsAsWaitingBecauseItCannotReportAQuestion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asking = directory.appendingPathComponent(AgentHooks.askingMarker).path
        AgentHooks.markWorking(.turnFinished, in: directory, protocol: .codex)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asking))
        AgentHooks.markWorking(.turnStarted, in: directory, protocol: .codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asking))
        // Claude reports its questions, so a finished turn there is finished.
        AgentHooks.markWorking(.turnFinished, in: directory, protocol: .claude)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asking))
    }

    /// The contract, one row per CLI: what it reports decides how its silence is read.
    func testEachCLIsProtocol() {
        XCTAssertEqual(AgentProtocol.of("claude"), .claude)
        XCTAssertEqual(AgentProtocol.of("codex"), .codex)
        XCTAssertEqual(AgentProtocol.of("gemini"), .silent)
        XCTAssertEqual(AgentProtocol.of(nil), .silent)
        XCTAssertFalse(AgentProtocol.claude.mustNotBeEndedWhileIdle, "Claude says when a turn ends")
        XCTAssertFalse(AgentProtocol.codex.mustNotBeEndedWhileIdle, "Codex says when a turn ends")
        XCTAssertTrue(AgentProtocol.silent.mustNotBeEndedWhileIdle, "nothing reports, so nothing is assumed idle")
        XCTAssertTrue(AgentHooks.reports("claude"))
        XCTAssertFalse(AgentHooks.reports("codex"))
    }
}
