import XCTest
@testable import DeskCore

/// Gemini, opencode and Antigravity became agent kinds so a start with one can be the default, remembered and
/// queued. These hold the two lines that change must not blur: a terminal run can use any of them, a background
/// run only Claude or Codex.
final class AgentKindTests: XCTestCase {
    func testEveryKindRoundTripsThroughTheNameAPreferenceStores() {
        for kind in AgentKind.allCases {
            XCTAssertEqual(AgentLaunch.agent(forConnectionName: AgentLaunch.connectionName(kind)), kind)
        }
        XCTAssertNil(AgentLaunch.agent(forConnectionName: "Cursor"))
    }

    /// A launch written before the new cases existed still reads, and one naming Gemini reads back as Gemini.
    func testARememberedLaunchKeepsItsAgent() throws {
        let launch = TaskLaunch(id: "task:9", task: "9", title: "t", door: "dev", arguments: ["#9"], agent: .gemini,
                                worktreeLocation: "~/.devdesk/wt")
        let decoded = try JSONDecoder().decode(TaskLaunch.self, from: JSONEncoder().encode(launch))
        XCTAssertEqual(decoded.agent, .gemini)
    }

    func testOnlyClaudeAndCodexRunInTheBackground() {
        XCTAssertEqual(AgentKind.allCases.filter(\.runsInBackground), [.claude, .codex])
        XCTAssertNotNil(DoorCommand.backgroundAgent(named: "Codex"))
        XCTAssertNil(DoorCommand.backgroundAgent(named: "Gemini"))
        XCTAssertNotNil(DoorCommand.agent(named: "Gemini"), "a terminal run may use it")
    }

    /// Before this, JobCommand read any non-claude agent as Codex and would have built `gemini exec --json`.
    func testABackgroundJobIsNeverBuiltForATerminalOnlyAgent() {
        XCTAssertNil(JobCommand.launch(door: "survey", agent: "Gemini", permission: .writeInRepo,
                                       directory: "/p", home: "/Users/me"))
        XCTAssertNil(ArchRun.launch(agent: "opencode", kind: "architecture", target: "", home: "/Users/me"))
    }

    /// A door run in a terminal with Gemini types the verified form, reading the family from Claude's root.
    func testATerminalDoorRunUsesTheVerifiedCommand() {
        let line = DoorCommand.build(door: "dev", agent: "Gemini", arguments: ["#9"], home: "/Users/me")
        XCTAssertEqual(line, "gemini --include-directories '/Users/me/.claude/skills/dev' -i "
            + "'Read /Users/me/.claude/skills/dev/SKILL.md and execute it exactly as written, following every phase "
            + "and gate it defines. Arguments: #9'")
    }

    /// An agent started from a task's own session gets the same verified argv, never `gemini <prompt>`.
    func testATaskAgentSessionUsesTheVerifiedArguments() {
        let arguments = AgentLaunch.arguments(agent: .antigravity, prompt: "p")
        XCTAssertEqual(arguments, ["agy", "--add-dir", AgentLaunch.skillRoot(for: .claude), "-i", "p"])
        XCTAssertEqual(AgentLaunch.arguments(agent: .codex, prompt: "p"), ["codex", "p"])
    }

    func testATerminalOnlyAgentIsReadyWhenInstalledAndSaysSoWhenNot() {
        guard case .ready(.gemini) = AgentAvailability.resolve(connectionName: "Gemini", connections: [],
                                                               terminalAgents: [.gemini]) else {
            return XCTFail("installed is all that can be known for Gemini")
        }
        guard case .unavailable(let reason) = AgentAvailability.resolve(connectionName: "opencode", connections: [],
                                                                        terminalAgents: [.gemini]) else {
            return XCTFail("not installed")
        }
        XCTAssertEqual(reason, "opencode isn't installed here, so Dev Desk can't start it.")
    }
}
