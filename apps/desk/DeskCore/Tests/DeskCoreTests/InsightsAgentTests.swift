import XCTest
@testable import DeskCore

final class InsightsAgentTests: XCTestCase {
    private let plan = InsightsAgentPlan(agent: .claude, repositoryRoot: "/repo", skillRoot: "/root/.claude/skills/dev")

    private func key(_ agent: AgentKind, _ question: String, skillRoot: String = "/root/.claude/skills/dev") -> String {
        let prompt = InsightsAgent.prompt(skillRoot: skillRoot, question: question)
        return ([agent.rawValue] + InsightsAgent.arguments(agent: agent, prompt: prompt)).joined(separator: " ")
    }

    func testPromptReadsTheInsightsDoorUnderTheInstallRoot() {
        XCTAssertEqual(InsightsAgent.prompt(skillRoot: "/root/.claude/skills/dev", question: "what is here?"),
                       "Read /root/.claude/skills/dev/skills/insights/SKILL.md and execute it exactly as written, "
                       + "following every phase and gate it defines. Arguments: what is here?")
        // A trailing separator is not doubled, the way os.path.join wouldn't.
        XCTAssertTrue(InsightsAgent.prompt(skillRoot: "/root/", question: "x").hasPrefix("Read /root/skills/insights/SKILL.md "))
    }

    /// The one place in the family that runs an agent non-interactively (ADR 0030).
    func testArgumentsAreTheVerifiedHeadlessForms() {
        XCTAssertEqual(InsightsAgent.arguments(agent: .claude, prompt: "p"), ["-p", "p"])
        XCTAssertEqual(InsightsAgent.arguments(agent: .codex, prompt: "p"), ["exec", "p"])
    }

    func testSuccessfulRunAnswersInTheRepositoryWithAGenerousTimeout() async throws {
        let runner = FakeRunner([key(.claude, "who calls load?"): .ok("ProjectWindowModel calls it.\n")])
        let answer = try await InsightsAgent(runner: runner, plan: plan).ask("who calls load?")
        XCTAssertEqual(answer, InsightsAnswer(text: "ProjectWindowModel calls it."))
        XCTAssertEqual(runner.calls.first?.directory?.path, "/repo")
        XCTAssertEqual(runner.calls.first?.timeout, InsightsAgent.timeout)
        XCTAssertGreaterThan(InsightsAgent.timeout, CommandTimeout.git)
    }

    /// The door cites `file:line`; a line that is only a citation becomes the bubble's citation instead of its last sentence.
    func testTrailingCitationIsLiftedOutOfTheProse() async throws {
        let runner = FakeRunner([key(.claude, "where?"): .ok("It loads in the window model.\n\nProjectWindowModel.swift:238\n")])
        let answer = try await InsightsAgent(runner: runner, plan: plan).ask("where?")
        XCTAssertEqual(answer.text, "It loads in the window model.")
        XCTAssertEqual(answer.citation, "ProjectWindowModel.swift:238")
        // Prose that merely mentions a file is left exactly as the agent wrote it.
        XCTAssertEqual(InsightsAgent.answer(from: "See Insights.swift:68 for the enum.")?.citation, nil)
    }

    func testMissingToolAndFailedRunBothExplainThemselves() async {
        let missing = FakeRunner([key(.claude, "q"): CommandResult(status: 127, stdout: "", stderr: "")])
        await XCTAssertThrows(InsightsAgentError.toolMissing(.claude)) {
            _ = try await InsightsAgent(runner: missing, plan: self.plan).ask("q")
        }
        let failed = FakeRunner([key(.claude, "q"): .failed(1, stderr: "not authenticated\n")])
        await XCTAssertThrows(InsightsAgentError.failed("not authenticated")) {
            _ = try await InsightsAgent(runner: failed, plan: self.plan).ask("q")
        }
        await XCTAssertThrows(InsightsAgentError.failed("claude did not finish within 300 seconds.")) {
            _ = try await InsightsAgent(runner: ThrowingRunner(error: CommandError.timedOut(tool: "claude", seconds: 300)),
                                    plan: self.plan).ask("q")
        }
        let silent = FakeRunner([key(.claude, "q"): .ok("   \n")])
        await XCTAssertThrows(InsightsAgentError.empty(.claude)) {
            _ = try await InsightsAgent(runner: silent, plan: self.plan).ask("q")
        }
    }

    /// Cancellation is not an answer: a newer question drops the run in flight without saying anything in the conversation.
    func testCancellationIsRethrown() async {
        do {
            _ = try await InsightsAgent(runner: ThrowingRunner(error: CancellationError()), plan: plan).ask("q")
            XCTFail("expected a cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("expected a cancellation, got \(error)")
        }
    }

    func testAvailabilityPicksTheSignedInAgent() {
        let connections = [
            Connection(id: "codex", name: "Codex", state: .detected, label: "not signed in", isSignedOut: true),
            Connection(id: "claude", name: "Claude", state: .detected, label: "me@example.com"),
            Connection(id: "gemini", name: "Gemini", state: .detected, label: "found · not supported"),
        ]
        XCTAssertEqual(InsightsAgent.availability(connections: connections, repositoryRoot: "/repo",
                                                  skillRoot: "/root", noAgentReason: "none"),
                       .live(InsightsAgentPlan(agent: .claude, repositoryRoot: "/repo", skillRoot: "/root")))
    }

    func testAvailabilityIsUnavailableWithoutAnAgentARepositoryOrASignIn() {
        let signedOut = [Connection(id: "claude", name: "Claude", state: .detected, label: "not signed in",
                                    detail: "Claude is installed but not signed in; a run would stop at its own prompt.",
                                    isSignedOut: true)]
        XCTAssertEqual(InsightsAgent.availability(connections: signedOut, repositoryRoot: "/repo", noAgentReason: "none"),
                       .unavailable("Claude is installed but not signed in; a run would stop at its own prompt."))

        // Gemini is found but unsupported, and a missing CLI is no connection at all: both leave the fallback reason.
        let noAgent = [Connection(id: "claude", name: "Claude", state: .missing, label: "not found"),
                       Connection(id: "gemini", name: "Gemini", state: .detected, label: "found · not supported")]
        XCTAssertEqual(InsightsAgent.availability(connections: noAgent, repositoryRoot: "/repo", noAgentReason: "none"),
                       .unavailable("none"))

        let ready = [Connection(id: "claude", name: "Claude", state: .detected, label: "me@example.com")]
        XCTAssertEqual(InsightsAgent.availability(connections: ready, repositoryRoot: nil, noAgentReason: "none"),
                       .unavailable(InsightsAgent.noRepositoryReason))
    }
}

/// A live conversation, driven by a fake agent rather than the script the demo replays.
@MainActor
final class InsightsLiveConversationTests: XCTestCase {
    private let plan = InsightsAgentPlan(agent: .claude, repositoryRoot: "/repo", skillRoot: "/root")

    private func key(_ question: String) -> String {
        ([plan.agent.rawValue] + InsightsAgent.arguments(agent: plan.agent,
                                                         prompt: InsightsAgent.prompt(skillRoot: plan.skillRoot, question: question)))
            .joined(separator: " ")
    }

    func testConfiguringLiveNamesTheAgentAndOpensTheComposer() {
        let conversation = InsightsConversation(delay: .zero, runner: FakeRunner())
        conversation.configure(.live(plan))
        XCTAssertEqual(conversation.provider, "Claude Code")
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertTrue(conversation.canAsk)
        XCTAssertNil(conversation.script)
    }

    func testAskingRunsTheAgentAndAppendsItsAnswer() async {
        let runner = FakeRunner([key("what is here?"): .ok("A Mac app.\n\nSKILL.md:1\n")])
        let conversation = InsightsConversation(delay: .zero, runner: runner)
        conversation.configure(.live(plan))
        conversation.draft = "what is here?"
        conversation.send()
        XCTAssertEqual(conversation.messages.last?.isUser, true)
        XCTAssertTrue(conversation.isReading)

        await waitUntil { !conversation.isReading }
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.last?.author, "Insights · Claude Code")
        XCTAssertEqual(conversation.messages.last?.text, "A Mac app.")
        XCTAssertEqual(conversation.messages.last?.citation, "SKILL.md:1")
    }

    func testAFailedRunIsSaidInTheConversation() async {
        let runner = FakeRunner([key("q"): CommandResult(status: 127, stdout: "", stderr: "")])
        let conversation = InsightsConversation(delay: .zero, runner: runner)
        conversation.configure(.live(plan))
        conversation.draft = "q"
        conversation.send()
        await waitUntil { !conversation.isReading }
        XCTAssertEqual(conversation.messages.last?.isUser, false)
        XCTAssertEqual(conversation.messages.last?.text, "Claude Code is not installed, so Insights can't answer.")
        XCTAssertNil(conversation.messages.last?.citation)
    }

    /// The demo path is untouched by any of this: no script, no agent, nothing sent.
    func testUnavailableStillAsksNothing() {
        let runner = FakeRunner()
        let conversation = InsightsConversation(delay: .zero, runner: runner)
        conversation.configure(.unavailable("no agent"))
        conversation.draft = "hi"
        conversation.send()
        XCTAssertFalse(conversation.canAsk)
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertTrue(runner.calls.isEmpty)
    }
}

extension XCTestCase {
    /// Asserts the exact error an async call throws, which XCTAssertThrowsError can't await.
    func XCTAssertThrows<E: Error & Equatable>(_ expected: E, _ body: () async throws -> Void,
                                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as E {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }
}
