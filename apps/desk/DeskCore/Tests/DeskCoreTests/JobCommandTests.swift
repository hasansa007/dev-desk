import XCTest
@testable import DeskCore

final class JobCommandTests: XCTestCase {
    private let home = "/Users/tester"
    private let directory = "/repo"

    private func launch(_ agent: String, _ permission: RunPermission) -> JobLaunch? {
        JobCommand.launch(door: "findings", agent: agent, permission: permission,
                          directory: directory, home: home, sessionID: "fixed-id")
    }

    func testClaudeIsGivenTheSessionIdTheAppChose() throws {
        let job = try XCTUnwrap(launch("Claude", .writeInRepo))
        XCTAssertEqual(job.executable, "claude")
        XCTAssertEqual(job.sessionID, "fixed-id")
        XCTAssertEqual(Array(job.arguments.prefix(8)),
                       ["-p", "--output-format", "stream-json", "--verbose", "--session-id", "fixed-id",
                        "--permission-mode", "acceptEdits"])
        XCTAssertEqual(job.arguments.last?.hasPrefix("Read /Users/tester/.claude/skills/dev/skills/findings/SKILL.md"), true)
    }

    func testEachPermissionLevelMapsToTheFlagsItsCliActuallyHas() throws {
        XCTAssertEqual(try XCTUnwrap(launch("Claude", .readOnly)).arguments.contains("plan"), true)
        XCTAssertEqual(try XCTUnwrap(launch("Claude", .everything)).arguments.contains("--dangerously-skip-permissions"), true)
        XCTAssertEqual(try XCTUnwrap(launch("Codex", .readOnly)).arguments.contains("read-only"), true)
        XCTAssertEqual(try XCTUnwrap(launch("Codex", .writeInRepo)).arguments.contains("workspace-write"), true)
        XCTAssertEqual(try XCTUnwrap(launch("Codex", .everything)).arguments.contains("danger-full-access"), true)
    }

    func testCodexRunsInTheProjectDirectoryAndHasNoIdToAssign() throws {
        let job = try XCTUnwrap(launch("Codex", .writeInRepo))
        XCTAssertEqual(Array(job.arguments.prefix(4)), ["exec", "--json", "-C", "/repo"])
        XCTAssertNil(job.sessionID, "codex has no --session-id, so the app must read one back")
    }

    func testAnAgentWithNoVerifiedInvocationLaunchesNothing() {
        XCTAssertNil(JobCommand.launch(door: "findings", agent: "Gemini", permission: .readOnly,
                                       directory: directory, home: home))
    }

    func testResumingClaudeContinuesTheSameSessionUnderTheSameGrant() throws {
        let job = try XCTUnwrap(JobCommand.resume(agent: "Claude", sessionID: "fixed-id", answer: "go", permission: .writeInRepo, home: home))
        XCTAssertEqual(job.arguments, ["-p", "--output-format", "stream-json", "--verbose", "--resume", "fixed-id",
                                       "--permission-mode", "acceptEdits", "go"])
    }

    func testResumingClaudeWithNoSessionIsRefusedRatherThanStartingANewOne() {
        XCTAssertNil(JobCommand.resume(agent: "Claude", sessionID: nil, answer: "go", permission: .readOnly, home: home))
    }

    func testResumingCodexFallsBackToItsMostRecentSession() throws {
        let job = try XCTUnwrap(JobCommand.resume(agent: "Codex", sessionID: nil, answer: "go", permission: .readOnly, home: home))
        XCTAssertEqual(job.arguments, ["exec", "resume", "--last", "--json", "--sandbox", "read-only", "go"])
    }

    /// Standard is the default: neither delegate flag is added, so today's argv is unchanged.
    func testStandardModeAddsNeitherDelegateFlag() throws {
        let claude = try XCTUnwrap(launch("Claude", .writeInRepo))
        XCTAssertFalse(claude.arguments.contains("--agents"))
        let codex = try XCTUnwrap(launch("Codex", .writeInRepo))
        XCTAssertFalse(codex.arguments.contains("--profile"))
    }

    /// Delegate gives claude a worker through `--agents`, whose value is JSON claude parses; asserting on the
    /// parse rather than the text keeps the check from breaking when the wording of the brief is edited.
    func testDelegateModeGivesClaudeAWorkerAsParsableJSON() throws {
        let job = try XCTUnwrap(JobCommand.launch(door: "findings", agent: "Claude", permission: .writeInRepo,
                                                  directory: directory, home: home, sessionID: "fixed-id", mode: .delegate))
        let index = try XCTUnwrap(job.arguments.firstIndex(of: "--agents"))
        XCTAssertTrue(job.arguments.indices.contains(index + 1))
        let data = try XCTUnwrap(job.arguments[index + 1].data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let worker = try XCTUnwrap(object["worker"] as? [String: Any])
        XCTAssertNotNil(worker["description"])
        XCTAssertNotNil(worker["prompt"])
    }

    /// Codex gets `--profile delegate` only when the profile file it names is actually there; naming a profile
    /// that is not there fails the run before the prompt is read, so the flag waits on the developer's file.
    func testDelegateModeGivesCodexTheProfileOnlyWhenItsFileExists() throws {
        let temp = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(atPath: temp) }

        let without = try XCTUnwrap(JobCommand.launch(door: "findings", agent: "Codex", permission: .writeInRepo,
                                                      directory: directory, home: temp, mode: .delegate))
        XCTAssertFalse(without.arguments.contains("--profile"), "no profile file means the flag would fail the run")

        try writeCodexDelegateProfile(under: temp)
        let with = try XCTUnwrap(JobCommand.launch(door: "findings", agent: "Codex", permission: .writeInRepo,
                                                   directory: directory, home: temp, mode: .delegate))
        let index = try XCTUnwrap(with.arguments.firstIndex(of: "--profile"))
        XCTAssertTrue(with.arguments.indices.contains(index + 1))
        XCTAssertEqual(with.arguments[index + 1], "delegate")
    }

    /// A delegate run resumed without its worker has nothing to hand to, so the mode's flags travel with the resume.
    func testResumingADelegateRunCarriesTheDelegateFlags() throws {
        let claude = try XCTUnwrap(JobCommand.resume(agent: "Claude", sessionID: "fixed-id", answer: "go",
                                                     permission: .writeInRepo, home: home, mode: .delegate))
        XCTAssertTrue(claude.arguments.contains("--agents"))

        let temp = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(atPath: temp) }
        try writeCodexDelegateProfile(under: temp)
        let codex = try XCTUnwrap(JobCommand.resume(agent: "Codex", sessionID: "s", answer: "go",
                                                    permission: .writeInRepo, home: temp, mode: .delegate))
        let index = try XCTUnwrap(codex.arguments.firstIndex(of: "--profile"))
        XCTAssertTrue(codex.arguments.indices.contains(index + 1))
        XCTAssertEqual(codex.arguments[index + 1], "delegate")
    }

    /// A temporary $CODEX_HOME so the profile check reads a real path this test owns, never the developer's.
    private func makeTemporaryHome() throws -> String {
        let path = NSTemporaryDirectory() + "delegate-home-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func writeCodexDelegateProfile(under home: String) throws {
        let codex = home + "/.codex"
        try FileManager.default.createDirectory(atPath: codex, withIntermediateDirectories: true)
        try "[profile]\n".write(toFile: codex + "/delegate.config.toml", atomically: true, encoding: .utf8)
    }

    /// The shape of a real run: one `result` event closes the stream, and its `result` is the last message.
    private let stream = """
    {"type":"system","subtype":"init","session_id":"cfe28379-afd8-43b9-9273-8a018c992d02"}
    {"type":"assistant","message":{"content":[{"type":"text","text":"Want me to start?"}]}}
    {"type":"result","subtype":"success","session_id":"cfe28379-afd8-43b9-9273-8a018c992d02","result":"Want me to start by looking at the untracked docs/ directory?","is_error":false,"permission_denials":[],"num_turns":1}
    """

    func testTheQuestionARunStoppedOnIsReadFromItsFinalEvent() throws {
        let outcome = try XCTUnwrap(JobLog.outcome(streamJSON: stream))
        XCTAssertEqual(outcome.sessionID, "cfe28379-afd8-43b9-9273-8a018c992d02")
        XCTAssertEqual(outcome.message, "Want me to start by looking at the untracked docs/ directory?")
        XCTAssertFalse(outcome.isError)
        XCTAssertEqual(outcome.denials, 0)
    }

    func testRefusedToolsAreCountedSoARunCanSayItWantedMoreThanItWasGiven() throws {
        let denied = """
        {"type":"result","subtype":"success","session_id":"s","result":"stopped","is_error":false,"permission_denials":[{"tool":"Bash"},{"tool":"Write"}]}
        """
        XCTAssertEqual(try XCTUnwrap(JobLog.outcome(streamJSON: denied)).denials, 2)
    }

    func testAStreamWithNoResultEventHasNoOutcomeYet() {
        XCTAssertNil(JobLog.outcome(streamJSON: "{\"type\":\"system\",\"subtype\":\"init\"}\n"))
    }
}
