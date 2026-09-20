import Foundation
import XCTest
@testable import DeskCore

final class AgentLaunchTests: XCTestCase {
    private static let root = "/Users/me/.claude/.dev-root"
    private static let read = "Read /Users/me/.claude/.dev-root/SKILL.md and execute it exactly as written, following every phase and gate it defines."

    /// Pinned to `dev run`'s prompt, scripts/dev.py:599-602:
    ///     extra = (" Arguments: " + " ".join(args)) if args else ""
    ///     return ("Read %s and execute it exactly as written, following every phase and gate it "
    ///             "defines.%s" % (door_path, extra))
    /// where door_path is os.path.join(skill_root(), "SKILL.md") for the dev door (scripts/dev.py:577-581).
    func testThePromptIsDevRunsBuildPromptByteForByte() {
        let numbered = AgentLaunch.prompt(skillRoot: Self.root, taskNumber: 42, hasBranch: false)
        XCTAssertEqual(Array(numbered.utf8), Array((Self.read + " Arguments: #42").utf8))
        let branched = AgentLaunch.prompt(skillRoot: Self.root, taskNumber: 42, hasBranch: true)
        XCTAssertEqual(Array(branched.utf8), Array(Self.read.utf8))
    }

    /// Delegate appends the same paragraph a door agent gets, after the ` Arguments: #N` clause, so a task agent and a
    /// door agent are asked for the same thing in the same words. Standard is unchanged, asserted byte for byte above.
    func testDelegateAppendsTheDoorsDelegationInstructionAfterTheArguments() {
        let delegate = AgentLaunch.prompt(skillRoot: Self.root, taskNumber: 42, hasBranch: false, mode: .delegate)
        let standard = Self.read + " Arguments: #42"
        XCTAssertEqual(Array(delegate.utf8), Array((standard + " " + DoorCommand.delegationInstruction).utf8),
                       "the arguments clause is still carried, then the shared instruction")
        XCTAssertTrue(delegate.contains(DoorCommand.delegationInstruction))
        XCTAssertTrue(delegate.contains(" Arguments: #42"))
    }

    func testStandardModeIsUnchangedByteForByte() {
        let numbered = AgentLaunch.prompt(skillRoot: Self.root, taskNumber: 42, hasBranch: false, mode: .standard)
        XCTAssertEqual(Array(numbered.utf8), Array((Self.read + " Arguments: #42").utf8))
        XCTAssertFalse(numbered.contains(DoorCommand.delegationInstruction), "standard mode adds nothing")
    }

    func testABranchOrNoNumberDropsTheArguments() {
        XCTAssertEqual(AgentLaunch.prompt(skillRoot: Self.root, taskNumber: 42, hasBranch: true), Self.read, "the branch already names the task")
        XCTAssertEqual(AgentLaunch.prompt(skillRoot: Self.root, taskNumber: nil, hasBranch: false), Self.read)
        XCTAssertEqual(AgentLaunch.prompt(skillRoot: Self.root, taskNumber: nil, hasBranch: true), Self.read)
    }

    func testTheDoorPathJoinsAsOsPathJoinDoes() {
        XCTAssertEqual(AgentLaunch.prompt(skillRoot: Self.root + "/", taskNumber: nil, hasBranch: false), Self.read, "no second slash")
    }

    func testTheCommandIsTheAgentThenThePromptAndNothingElse() {
        XCTAssertEqual(AgentLaunch.arguments(agent: .claude, prompt: Self.read), ["claude", Self.read])
        XCTAssertEqual(AgentLaunch.arguments(agent: .codex, prompt: Self.read), ["codex", Self.read])
        let hostile = "-p --dangerously-skip-permissions \"$(rm -rf ~)\" 'x'"
        XCTAssertEqual(AgentLaunch.arguments(agent: .codex, prompt: hostile), ["codex", hostile], "the prompt stays one element, never split or quoted")
    }

    func testConnectionNamesMapToTheAgentsDevDeskStarts() {
        XCTAssertEqual(AgentLaunch.agent(forConnectionName: "Claude"), .claude)
        XCTAssertEqual(AgentLaunch.agent(forConnectionName: "Codex"), .codex)
        // Terminal-only agents since 2026-09-16, each with a command run for real (TerminalAgent).
        XCTAssertEqual(AgentLaunch.agent(forConnectionName: "Gemini"), .gemini)
        XCTAssertEqual(AgentLaunch.agent(forConnectionName: "Antigravity"), .antigravity)
        XCTAssertNil(AgentLaunch.agent(forConnectionName: "Cursor"))
        XCTAssertNil(AgentLaunch.agent(forConnectionName: ""))
    }

    func testDisplayNames() {
        XCTAssertEqual(AgentLaunch.displayName(.claude), "Claude Code")
        XCTAssertEqual(AgentLaunch.displayName(.codex), "Codex")
    }

    func testEachAgentReadsItsOwnSkillRootWithTheTildeExpanded() {
        for agent in [AgentKind.claude, .codex] {
            let root = AgentLaunch.skillRoot(for: agent)
            XCTAssertFalse(root.contains("~"), root)
            XCTAssertTrue(root.hasPrefix("/"), root)
        }
        // install.sh writes one copy per agent; sending Codex to Claude's copy is what this pins shut.
        let onlyDevRoot: (String) -> Bool = { $0 == "/Users/me/.claude/.dev-root" }
        XCTAssertEqual(AgentLaunch.skillRoot(for: .claude, home: "/Users/me", exists: onlyDevRoot),
                       "/Users/me/.claude/.dev-root")
        XCTAssertEqual(AgentLaunch.skillRoot(for: .codex, home: "/Users/me", exists: onlyDevRoot),
                       "/Users/me/.codex/skills/dev")
    }

    /// A machine installed before ADR 0054 has no `.dev-root`, and the per-CLI link install.sh still wrote is
    /// the family. Reading the new root there is the same defect in the other direction.
    func testClaudeFallsBackToThePerCLILinkOnAPre0054Install() {
        let onlyOldLink: (String) -> Bool = { $0 == "/Users/me/.claude/skills/dev" }
        XCTAssertEqual(AgentLaunch.skillRoot(for: .claude, home: "/Users/me", exists: onlyOldLink),
                       "/Users/me/.claude/skills/dev")
    }
}
