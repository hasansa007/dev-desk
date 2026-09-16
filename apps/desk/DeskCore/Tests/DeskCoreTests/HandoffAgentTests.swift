import XCTest
@testable import DeskCore

/// The hand-off commands are the ones that ran on 2026-09-16, byte for byte: a guessed flag is a terminal that
/// opens and fails in front of the developer.
final class HandoffAgentTests: XCTestCase {
    let root = "/Users/me/.claude/skills/dev"

    func testEachCommandStaysInteractiveAndGivesTheFamilyFolderWhereTheToolFencesItsFiles() {
        let prompt = "Read /Users/me/.claude/skills/dev/SKILL.md and execute it."
        XCTAssertEqual(HandoffAgent.gemini.command(prompt: prompt, familyRoot: root),
                       "gemini --include-directories '/Users/me/.claude/skills/dev' -i '\(prompt)'")
        XCTAssertEqual(HandoffAgent.opencode.command(prompt: prompt, familyRoot: root),
                       "opencode --prompt '\(prompt)'")
        XCTAssertEqual(HandoffAgent.antigravity.command(prompt: prompt, familyRoot: root),
                       "agy --add-dir '/Users/me/.claude/skills/dev' -i '\(prompt)'")
    }

    /// A card title can carry a quote; it must not end the shell string early.
    func testAQuoteInThePromptCannotEndTheShellString() {
        let command = HandoffAgent.opencode.command(prompt: "fix the user's upload", familyRoot: root)
        XCTAssertEqual(command, "opencode --prompt 'fix the user'\\''s upload'")
    }

    /// Antigravity's CLI is `agy`, not its product name — `which antigravity` finds nothing on a Mac that has it.
    func testDetectionAsksForEachExecutableAndOffersOnlyWhatAnswered() async {
        let runner = FakeRunner(["which gemini": .ok("/opt/homebrew/bin/gemini\n"),
                                 "which agy": .ok("/Users/me/.local/bin/agy\n")])
        let found = await HandoffAgent.detect(runner: runner)
        XCTAssertEqual(found, [.gemini, .antigravity])
        XCTAssertEqual(Set(runner.keys), ["which gemini", "which opencode", "which agy"])
    }
}
