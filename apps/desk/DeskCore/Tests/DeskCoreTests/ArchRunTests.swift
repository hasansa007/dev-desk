import XCTest
@testable import DeskCore

final class ArchRunTests: XCTestCase {
    private let home = "/Users/tester"

    /// The prompt reads the arch SKILL and carries the target first, the kind last — the door's own argument order.
    func testThePromptCarriesTheTargetThenTheKind() {
        let prompt = ArchRun.prompt(agent: "Codex", kind: "dataflow", target: "the auth flow", home: home)
        XCTAssertEqual(prompt?.hasPrefix("Read /Users/tester/.codex/skills/dev/skills/arch/SKILL.md"), true)
        XCTAssertEqual(prompt?.hasSuffix("Arguments: the auth flow dataflow"), true)
    }

    /// An empty target draws the whole project: only the kind is passed.
    func testAnEmptyTargetPassesOnlyTheKind() {
        let prompt = ArchRun.prompt(agent: "Claude", kind: "architecture", target: "  ", home: home)
        XCTAssertEqual(prompt?.hasSuffix("Arguments: architecture"), true)
    }

    /// The headless argv is the verified `exec`/`-p` form. Codex's flags each take one value, so its prompt
    /// is the single final element; claude's `--allowedTools` is variadic and consumed a trailing prompt as
    /// one more tool name (the CLI then exited 1, given no prompt at all), so claude's prompt sits
    /// immediately after `-p`, before every flag.
    func testTheHeadlessArgvIsTheVerifiedFormPerCLI() throws {
        let codex = try XCTUnwrap(ArchRun.launch(agent: "Codex", kind: "workflow", target: "", home: home))
        XCTAssertEqual(Array(codex.dropLast()), ["codex", "exec", "-s", "workspace-write"])
        XCTAssertEqual(codex.last, ArchRun.prompt(agent: "Codex", kind: "workflow", target: "", home: home))

        let prompt = try XCTUnwrap(ArchRun.prompt(agent: "Claude", kind: "sequence", target: "checkout", home: home))
        let claude = try XCTUnwrap(ArchRun.launch(agent: "Claude", kind: "sequence", target: "checkout", home: home))
        XCTAssertEqual(claude, ["claude", "-p", prompt,
                                "--permission-mode", "acceptEdits",
                                "--allowedTools", "Bash Read Write Edit Glob Grep"])
        // The kind reaches the prompt, so the run draws the type that was asked for.
        XCTAssertEqual(prompt.contains(" checkout sequence"), true)
    }

    /// The regression itself: with a variadic flag in the argv the prompt must never be the final element —
    /// trailing there is exactly where `--allowedTools` swallowed it.
    func testTheClaudePromptIsNeverBehindTheVariadicFlag() throws {
        let prompt = try XCTUnwrap(ArchRun.prompt(agent: "Claude", kind: "architecture", target: "", home: home))
        let claude = try XCTUnwrap(ArchRun.launch(agent: "Claude", kind: "architecture", target: "", home: home))
        XCTAssertTrue(claude.contains(where: HeadlessArgv.variadicFlags.contains),
                      "this run carries a variadic flag; if that ever changes, the prompt may trail again")
        XCTAssertNotEqual(claude.last, prompt)
        XCTAssertEqual(claude.firstIndex(of: prompt), 2, "the prompt sits right after -p, before any flag")
    }

    /// A CLI the family has no verified headless invocation for gets no argv.
    func testAnUnknownAgentGetsNoArgv() {
        XCTAssertNil(ArchRun.launch(agent: "Gemini", kind: "architecture", target: "", home: home))
        XCTAssertNil(ArchRun.prompt(agent: "Gemini", kind: "architecture", target: "", home: home))
    }
}
