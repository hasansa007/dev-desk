import XCTest
@testable import DeskCore

final class ArchRunTests: XCTestCase {
    private let home = "/Users/tester"

    /// The prompt reads the arch SKILL and carries the target first, the kind last — the door's own argument order.
    func testThePromptCarriesTheTargetThenTheKind() {
        let prompt = ArchRun.prompt(agent: "Codex", kind: "dataflow", target: "the auth flow", home: home)
        XCTAssertEqual(prompt?.hasPrefix("Read /Users/tester/.codex/skills/dev/skills/arch/SKILL.md"), true)
        XCTAssertEqual(prompt?.contains("Arguments: the auth flow dataflow "), true)
    }

    /// An empty target draws the whole project: only the kind is passed.
    func testAnEmptyTargetPassesOnlyTheKind() {
        let prompt = ArchRun.prompt(agent: "Claude", kind: "architecture", target: "  ", home: home)
        XCTAssertEqual(prompt?.contains("Arguments: architecture "), true)
    }

    /// The screen's answers ride on every prompt, so the run neither asks for a target nor cuts a branch over
    /// the developer's work.
    func testTheRunCarriesTheScreensAnswers() throws {
        for agent in ["Codex", "Claude"] {
            let prompt = try XCTUnwrap(ArchRun.prompt(agent: agent, kind: "dataflow", target: "", home: home))
            XCTAssertTrue(prompt.hasSuffix(ArchRun.screenInstruction))
            XCTAssertTrue(prompt.contains("Do not cut a branch"))
        }
    }

    /// Interactive, like every other door: the CLI and its prompt, no `-p`/`exec`, so the terminal shows the run.
    func testTheArgvIsInteractive() throws {
        for (agent, executable) in [("Claude", "claude"), ("Codex", "codex")] {
            let prompt = try XCTUnwrap(ArchRun.prompt(agent: agent, kind: "sequence", target: "checkout", home: home))
            XCTAssertEqual(ArchRun.launch(agent: agent, kind: "sequence", target: "checkout", home: home), [executable, prompt])
            XCTAssertTrue(prompt.contains(" checkout sequence "))
        }
    }

    /// A CLI the family has no verified headless invocation for gets no argv.
    func testAnUnknownAgentGetsNoArgv() {
        XCTAssertNil(ArchRun.launch(agent: "Gemini", kind: "architecture", target: "", home: home))
        XCTAssertNil(ArchRun.prompt(agent: "Gemini", kind: "architecture", target: "", home: home))
    }

    /// A flow's sequence is named so the screen can find it again.
    func testAFlowSequenceIsNamed() throws {
        let prompt = try XCTUnwrap(ArchRun.prompt(agent: "Claude", kind: "sequence", target: "Build a course",
                                                  home: home, outputName: "app-sequence-build-a-course"))
        XCTAssertTrue(prompt.hasSuffix("Name the files docs/arch/app-sequence-build-a-course.html and its sidecar docs/arch/app-sequence-build-a-course.sequence.json."))
    }
}
