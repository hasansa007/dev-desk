import XCTest
@testable import DeskCore

@MainActor
final class DoorRunsTests: XCTestCase {
    private let home = "/Users/tester"

    func testClaudeReadsTheDoorFromItsOwnInstallRoot() {
        XCTAssertEqual(DoorCommand.build(door: "findings", agent: "Claude", home: home),
                       "claude 'Read /Users/tester/.claude/.dev-root/skills/findings/SKILL.md and execute it exactly as written, "
                       + "following every phase and gate it defines.'")
    }

    func testCodexReadsTheDoorFromTheCodexRoot() {
        let command = DoorCommand.build(door: "ideation", agent: "codex", home: home)
        XCTAssertEqual(command?.hasPrefix("codex 'Read /Users/tester/.codex/skills/dev/skills/ideation/SKILL.md"), true)
    }

    func testTheRootDoorIsTheFamilysOwnSkillFile() {
        XCTAssertEqual(DoorCommand.doorPath("dev", root: InstallRoot.claude, home: home),
                       "/Users/tester/.claude/.dev-root/SKILL.md")
    }

    func testArgumentsAreAppendedForTheDoorToRead() {
        let command = DoorCommand.build(door: "ideation", agent: "Claude", arguments: ["--perf", "--security"], home: home)
        XCTAssertEqual(command?.hasSuffix("Arguments: --perf --security'"), true)
    }

    func testAQuoteInAnArgumentCannotEndTheQuoting() {
        let command = DoorCommand.build(door: "findings", agent: "Claude", arguments: ["'; rm -rf ~"], home: home)
        XCTAssertEqual(command?.contains("'\\''"), true)
        XCTAssertEqual(command?.hasSuffix("'"), true)
    }

    /// Gemini has a verified terminal command now (AgentKindTests); a tool with none still gets nothing.
    func testAnAgentWithNoVerifiedInvocationGetsNoCommand() {
        XCTAssertNil(DoorCommand.build(door: "findings", agent: "Cursor", home: home))
    }

    /// Standard is the default, and the default is what every existing caller and `scripts/dev.py` agree on.
    func testStandardModeIsTheSameCommandAsNoModeAtAll() {
        XCTAssertEqual(DoorCommand.build(door: "findings", agent: "Claude", home: home, mode: .standard),
                       DoorCommand.build(door: "findings", agent: "Claude", home: home))
        XCTAssertEqual(DoorCommand.prompt(door: "dev", agent: "Codex", arguments: ["#4"], home: home, mode: .standard)?
                        .contains("orchestrator"), false)
    }

    /// Delegate keeps the door and its arguments as they were and adds to them, so the door is still followed
    /// exactly as written — only the way its steps are carried out changes.
    func testDelegateModeAppendsTheDelegationInstructionAfterTheArguments() throws {
        let prompt = try XCTUnwrap(DoorCommand.prompt(door: "dev", agent: "Claude", arguments: ["#12"], home: home, mode: .delegate))
        XCTAssertEqual(prompt.hasPrefix("Read /Users/tester/.claude/.dev-root/SKILL.md and execute it exactly as written, "
                                        + "following every phase and gate it defines. Arguments: #12 "), true)
        XCTAssertEqual(prompt.hasSuffix(DoorCommand.delegationInstruction), true)
        XCTAssertTrue(prompt.contains("worker subagent"))
        XCTAssertTrue(prompt.contains("door's own gates"))
    }

    func testDelegateModeIsQuotedLikeAnyOtherCommand() throws {
        let command = try XCTUnwrap(DoorCommand.build(door: "findings", agent: "Codex", home: home, mode: .delegate))
        XCTAssertEqual(command.hasPrefix("codex 'Read /Users/tester/.codex/skills/dev/skills/findings/SKILL.md"), true)
        XCTAssertEqual(command.hasSuffix("cost more than the change.'"), true)
    }

    func testStartingTheSameDoorTwiceKeepsOneRow() {
        let runs = DoorRuns()
        runs.add(DoorRun(id: "findings", title: "Findings", agent: "Claude", command: "a", folderNote: ""))
        runs.add(DoorRun(id: "findings", title: "Findings", agent: "Codex", command: "b", folderNote: ""))
        XCTAssertEqual(runs.runs.count, 1)
        XCTAssertEqual(runs.runs.first?.agent, "Codex")
        XCTAssertEqual(runs.selectedID, "findings")
    }

    /// A findings run is identified by the half it writes, so two scopes are two rows and two shells — while the
    /// same scope asked for twice is the same id, which is what `prepareRun` refuses.
    func testAFindingsRunsIdCarriesItsScope() {
        XCTAssertEqual(DoorRuns.id(door: "findings", scope: .defects), "door:findings:defects")
        XCTAssertNotEqual(DoorRuns.id(door: "findings", scope: .defects), DoorRuns.id(door: "findings", scope: .architecture))
        XCTAssertNotEqual(DoorRuns.id(door: "findings", scope: .both), DoorRuns.id(door: "findings"))
        let runs = DoorRuns()
        runs.add(DoorRun(id: DoorRuns.id(door: "findings", scope: .defects), title: "Findings · Defects",
                         agent: "Claude", command: "a", folderNote: ""))
        runs.add(DoorRun(id: DoorRuns.id(door: "findings", scope: .architecture), title: "Findings · Architecture",
                         agent: "Claude", command: "b", folderNote: ""))
        XCTAssertEqual(runs.runs.count, 2, "the two halves are two runs, not one row overwritten")
    }

    /// The rule the registry and the window both ask: the same half never twice, the two halves together,
    /// and `both` — which writes the whole report — beside nothing at all.
    func testTheScopeConflictRule() {
        XCTAssertTrue(FindingsRunScope.defects.conflicts(with: .defects))
        XCTAssertFalse(FindingsRunScope.defects.conflicts(with: .architecture))
        XCTAssertFalse(FindingsRunScope.architecture.conflicts(with: .defects))
        for scope in FindingsRunScope.allCases {
            XCTAssertTrue(FindingsRunScope.both.conflicts(with: scope))
            XCTAssertTrue(scope.conflicts(with: .both))
        }
        XCTAssertEqual(FindingsRunScope(recorded: nil), .both, "a run that named no half may have written either")
        XCTAssertEqual(FindingsRunScope(recorded: "defects"), .defects)
        XCTAssertEqual(FindingsRunScope.allCases.map(\.runTitle), ["Findings", "Findings · Defects", "Findings · Architecture"])
    }

    func testRemovingTheSelectedRunSelectsAnotherOne() {
        let runs = DoorRuns()
        runs.add(DoorRun(id: "findings", title: "Findings", agent: "Claude", command: "a", folderNote: ""))
        runs.add(DoorRun(id: "ideation", title: "Ideation", agent: "Claude", command: "b", folderNote: ""))
        runs.remove("ideation")
        XCTAssertEqual(runs.selectedID, "findings")
        XCTAssertNil(runs.run("ideation"))
    }
}
