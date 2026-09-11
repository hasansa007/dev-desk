import Foundation
import XCTest
@testable import DeskCore

final class AgentLaunchTests: XCTestCase {
    private static let root = "/Users/me/.claude/skills/dev"
    private static let read = "Read /Users/me/.claude/skills/dev/SKILL.md and execute it exactly as written, following every phase and gate it defines."

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
        XCTAssertNil(AgentLaunch.agent(forConnectionName: "Gemini"), "no confirmed way to run the dev pipeline")
        XCTAssertNil(AgentLaunch.agent(forConnectionName: "Antigravity"))
        XCTAssertNil(AgentLaunch.agent(forConnectionName: ""))
    }

    func testDisplayNames() {
        XCTAssertEqual(AgentLaunch.displayName(.claude), "Claude Code")
        XCTAssertEqual(AgentLaunch.displayName(.codex), "Codex")
    }

    func testTheSkillRootIsTheDevSkillFolderWithTheTildeExpanded() {
        let root = AgentLaunch.skillRoot
        XCTAssertFalse(root.contains("~"), root)
        XCTAssertTrue(root.hasPrefix("/"), root)
        XCTAssertEqual(root, (ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()) + "/.claude/skills/dev",
                       "the home os.path.expanduser reads")
    }
}
