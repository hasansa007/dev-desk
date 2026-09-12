import XCTest
@testable import DeskCore

@MainActor
final class DoorRunsTests: XCTestCase {
    private let home = "/Users/tester"

    func testClaudeReadsTheDoorFromItsOwnInstallRoot() {
        XCTAssertEqual(DoorCommand.build(door: "survey", agent: "Claude", home: home),
                       "claude 'Read /Users/tester/.claude/skills/dev/skills/survey/SKILL.md and execute it exactly as written, "
                       + "following every phase and gate it defines.'")
    }

    func testCodexReadsTheDoorFromTheCodexRoot() {
        let command = DoorCommand.build(door: "ideation", agent: "codex", home: home)
        XCTAssertEqual(command?.hasPrefix("codex 'Read /Users/tester/.codex/skills/dev/skills/ideation/SKILL.md"), true)
    }

    func testTheRootDoorIsTheFamilysOwnSkillFile() {
        XCTAssertEqual(DoorCommand.doorPath("dev", root: ".claude/skills/dev", home: home),
                       "/Users/tester/.claude/skills/dev/SKILL.md")
    }

    func testArgumentsAreAppendedForTheDoorToRead() {
        let command = DoorCommand.build(door: "ideation", agent: "Claude", arguments: ["--perf", "--security"], home: home)
        XCTAssertEqual(command?.hasSuffix("Arguments: --perf --security'"), true)
    }

    func testAQuoteInAnArgumentCannotEndTheQuoting() {
        let command = DoorCommand.build(door: "survey", agent: "Claude", arguments: ["'; rm -rf ~"], home: home)
        XCTAssertEqual(command?.contains("'\\''"), true)
        XCTAssertEqual(command?.hasSuffix("'"), true)
    }

    func testAnAgentWithNoVerifiedInvocationGetsNoCommand() {
        XCTAssertNil(DoorCommand.build(door: "survey", agent: "Gemini", home: home))
    }

    func testStartingTheSameDoorTwiceKeepsOneRow() {
        let runs = DoorRuns()
        runs.add(DoorRun(id: "survey", title: "Survey", agent: "Claude", command: "a", folderNote: ""))
        runs.add(DoorRun(id: "survey", title: "Survey", agent: "Codex", command: "b", folderNote: ""))
        XCTAssertEqual(runs.runs.count, 1)
        XCTAssertEqual(runs.runs.first?.agent, "Codex")
        XCTAssertEqual(runs.selectedID, "survey")
    }

    func testRemovingTheSelectedRunSelectsAnotherOne() {
        let runs = DoorRuns()
        runs.add(DoorRun(id: "survey", title: "Survey", agent: "Claude", command: "a", folderNote: ""))
        runs.add(DoorRun(id: "ideation", title: "Ideation", agent: "Claude", command: "b", folderNote: ""))
        runs.remove("ideation")
        XCTAssertEqual(runs.selectedID, "survey")
        XCTAssertNil(runs.run("ideation"))
    }
}
