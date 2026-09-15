import XCTest
@testable import DeskCore

/// The one rule every headless launcher builds its argv through: the prompt is the single final element until
/// a variadic flag is present, and then it moves in front of the flags, where nothing can consume it.
final class HeadlessArgvTests: XCTestCase {
    /// Flags that each take exactly one value keep the verified shape: flags first, prompt last.
    func testASingleValueArgvKeepsThePromptLast() {
        XCTAssertEqual(HeadlessArgv.argv(head: ["codex", "exec"], flags: ["-s", "workspace-write"], prompt: "draw it"),
                       ["codex", "exec", "-s", "workspace-write", "draw it"])
    }

    /// A known variadic flag repositions the prompt to just after the head: left trailing, it would be read
    /// as one more of that flag's values, and the CLI would exit having been given no prompt at all.
    func testAVariadicFlagMovesThePromptInFrontOfTheFlags() {
        let argv = HeadlessArgv.argv(head: ["claude", "-p"],
                                     flags: ["--permission-mode", "acceptEdits", "--allowedTools", "Bash Read"],
                                     prompt: "draw it")
        XCTAssertEqual(argv, ["claude", "-p", "draw it",
                              "--permission-mode", "acceptEdits", "--allowedTools", "Bash Read"])
        XCTAssertNotEqual(argv.last, "draw it")
    }

    /// Every documented variadic flag — both spellings of claude's tool lists, and codex's image flag — is
    /// caught, so a launcher that later passes one cannot leave the prompt where it gets eaten.
    func testEveryDocumentedVariadicFlagIsCaught() {
        for flag in ["--add-dir", "--allowedTools", "--allowed-tools", "--betas",
                     "--disallowedTools", "--disallowed-tools", "--file", "--mcp-config", "--tools",
                     "-i", "--image"] {
            XCTAssertNotEqual(HeadlessArgv.argv(head: ["cli"], flags: [flag, "value"], prompt: "p").last, "p",
                              "\(flag) is variadic; a prompt after it would be consumed")
        }
    }
}
