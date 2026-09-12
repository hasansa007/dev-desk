import XCTest
@testable import DeskCore

final class JobCommandTests: XCTestCase {
    private let home = "/Users/tester"
    private let directory = "/repo"

    private func launch(_ agent: String, _ permission: RunPermission) -> JobLaunch? {
        JobCommand.launch(door: "survey", agent: agent, permission: permission,
                          directory: directory, home: home, sessionID: "fixed-id")
    }

    func testClaudeIsGivenTheSessionIdTheAppChose() throws {
        let job = try XCTUnwrap(launch("Claude", .writeInRepo))
        XCTAssertEqual(job.executable, "claude")
        XCTAssertEqual(job.sessionID, "fixed-id")
        XCTAssertEqual(Array(job.arguments.prefix(8)),
                       ["-p", "--output-format", "stream-json", "--verbose", "--session-id", "fixed-id",
                        "--permission-mode", "acceptEdits"])
        XCTAssertEqual(job.arguments.last?.hasPrefix("Read /Users/tester/.claude/skills/dev/skills/survey/SKILL.md"), true)
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
        XCTAssertNil(JobCommand.launch(door: "survey", agent: "Gemini", permission: .readOnly,
                                       directory: directory, home: home))
    }

    func testResumingClaudeContinuesTheSameSession() throws {
        let job = try XCTUnwrap(JobCommand.resume(agent: "Claude", sessionID: "fixed-id", answer: "go"))
        XCTAssertEqual(job.arguments, ["-p", "--output-format", "stream-json", "--verbose", "--resume", "fixed-id", "go"])
    }

    func testResumingClaudeWithNoSessionIsRefusedRatherThanStartingANewOne() {
        XCTAssertNil(JobCommand.resume(agent: "Claude", sessionID: nil, answer: "go"))
    }

    func testResumingCodexFallsBackToItsMostRecentSession() throws {
        let job = try XCTUnwrap(JobCommand.resume(agent: "Codex", sessionID: nil, answer: "go"))
        XCTAssertEqual(job.arguments, ["exec", "resume", "--last", "--json", "go"])
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
