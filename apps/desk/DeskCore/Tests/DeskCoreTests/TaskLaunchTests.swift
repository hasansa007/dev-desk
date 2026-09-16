import XCTest
@testable import DeskCore

@MainActor
final class TaskLaunchTests: XCTestCase {
    private let home = "/Users/tester"

    private func launch(agent: AgentKind = .claude, mode: RunMode = .standard, door: String = "dev",
                        arguments: [String] = ["#212"]) -> TaskLaunch {
        TaskLaunch(id: DoorRuns.id(task: 212), task: "212", title: "Resume upload fails over 20 MB",
                   door: door, arguments: arguments, agent: agent, mode: mode,
                   worktreeLocation: "~/.devdesk/wt",
                   base: LaunchBase(ref: "origin/main", short: "8c1f2a0"))
    }

    func testThePromptIsTheOneScriptsDevPyBuilds() {
        let expected = "Read /Users/tester/.claude/skills/dev/SKILL.md and execute it exactly as written, "
            + "following every phase and gate it defines. Arguments: #212"
        XCTAssertEqual(launch().prompt(home: home), expected)
    }

    /// The defect this type removes: AgentLaunch.prompt sent both CLIs to ~/.claude/skills/dev, and
    /// scripts/dev.py did the same, so a Codex run read the Claude copy of the door.
    func testEachAgentIsSentToItsOwnSkillRoot() {
        XCTAssertEqual(launch(agent: .claude).prompt(home: home)?.contains("/.claude/skills/dev/SKILL.md"), true)
        XCTAssertEqual(launch(agent: .codex).prompt(home: home)?.contains("/.codex/skills/dev/SKILL.md"), true)
        XCTAssertNotEqual(launch(agent: .claude).prompt(home: home), launch(agent: .codex).prompt(home: home))
    }

    func testADoorThatIsNotTheRootReadsItsOwnSkillFile() {
        let prompt = launch(door: "findings", arguments: []).prompt(home: home)
        XCTAssertEqual(prompt?.contains("/.claude/skills/dev/skills/findings/SKILL.md"), true)
        XCTAssertEqual(prompt?.contains("Arguments:"), false, "no arguments means no arguments clause")
    }

    func testDelegateAppendsToThePromptRatherThanRewordingIt() {
        let standard = launch(mode: .standard).prompt(home: home) ?? ""
        let delegate = launch(mode: .delegate).prompt(home: home) ?? ""
        XCTAssertTrue(delegate.hasPrefix(standard), "delegate must not reword the door's own instruction")
        XCTAssertTrue(delegate.contains(DoorCommand.delegationInstruction))
    }

    func testTheCommandQuotesThePromptSoADoorsArgumentsCannotEndTheString() {
        let command = launch(arguments: ["it's #212"]).command(home: home) ?? ""
        XCTAssertTrue(command.hasPrefix("claude '"))
        XCTAssertTrue(command.contains("'\\''"), "a quote is closed, escaped and reopened")
    }

    func testABasePinsTheCommitAndNotJustTheRef() {
        XCTAssertEqual(launch().base?.display, "origin/main@8c1f2a0")
        XCTAssertEqual(LaunchBase(ref: "origin/main", short: nil).display, "origin/main",
                       "a ref with no resolved commit still reads as itself")
    }

    /// The queue bug this type fixes: today a queued card stores nothing and the agent and mode are
    /// re-read from UserDefaults when a slot frees, so the preferences at release time win.
    func testALaunchSurvivesAQueueUnchanged() throws {
        let queued = launch(agent: .codex, mode: .delegate)
        let data = try JSONEncoder().encode(queued)
        let released = try JSONDecoder().decode(TaskLaunch.self, from: data)

        XCTAssertEqual(released, queued, "a launch must equal itself after a round trip, timestamp included")
        XCTAssertEqual(released.agent, .codex)
        XCTAssertEqual(released.mode, .delegate)
        XCTAssertEqual(released.worktreeLocation, "~/.devdesk/wt")
        XCTAssertEqual(released.base?.display, "origin/main@8c1f2a0")
        XCTAssertEqual(released.prompt(home: home), queued.prompt(home: home))
    }

    func testTheLaunchCarriesNoWorktreePlan() throws {
        // The plan reads `git worktree list`, so one pinned when a card was queued can be wrong by
        // the time a slot frees. The location it resolves against is the decision worth keeping.
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(launch()), encoding: .utf8))
        XCTAssertFalse(json.contains("folder"))
        XCTAssertTrue(json.contains("worktreeLocation"))
    }
}
