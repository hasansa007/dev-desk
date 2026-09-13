import Foundation
import XCTest
@testable import DeskCore

/// Recorded output from `claude -p --output-format stream-json` (2.1.270) and `codex exec --json` (0.154.0),
/// for the same reason `JobStreamTests` uses recorded text: a parser exercised only by starting an agent spends
/// the developer's tokens to run, and so is never re-run.
final class ContextUsageTests: XCTestCase {
    /// The three input fields are what the model was sent, and Claude reports them apart. Only their sum is
    /// "in context"; `output_tokens` is what the turn produced and belongs to no context.
    func testClaudeSumsItsThreeInputFields() throws {
        let line = #"{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":2091,"cache_read_input_tokens":140679,"output_tokens":614}}}"#
        let usage = try XCTUnwrap(ContextUsage.claude(line: line))
        XCTAssertEqual(usage.used, 142_772)
    }

    /// Claude's stream states no context window anywhere, so there is no denominator to divide by — and a
    /// guessed one would read as a measurement.
    func testClaudeHasNoPercentageBecauseItReportsNoWindow() throws {
        let line = #"{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":90}}}"#
        let usage = try XCTUnwrap(ContextUsage.claude(line: line))
        XCTAssertNil(usage.window)
        XCTAssertNil(usage.percent)
        XCTAssertEqual(usage.label, "100 tokens")
    }

    /// The final `result` event carries the same object one level up.
    func testClaudeReadsTheResultEventsUsage() throws {
        let line = #"{"type":"result","subtype":"success","result":"Done","usage":{"input_tokens":5,"cache_creation_input_tokens":5,"cache_read_input_tokens":10,"output_tokens":900}}"#
        XCTAssertEqual(ContextUsage.claude(line: line), ContextUsage(used: 20))
    }

    func testALineWithNoUsageIsNotAReading() {
        XCTAssertNil(ContextUsage.claude(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#))
        XCTAssertNil(ContextUsage.claude(line: "not json at all"))
        XCTAssertNil(ContextUsage.codex(line: #"{"type":"item.completed"}"#))
    }

    /// `codex exec --json` writes the event bare on its stream. What is in context now is the last turn's
    /// total, and the window is stated, so this is the one agent with a percentage.
    func testCodexReadsTheBareTokenCountAndItsWindow() throws {
        let usage = try XCTUnwrap(ContextUsage.codex(line: Self.codexBare))
        XCTAssertEqual(usage.used, 17_379)
        XCTAssertEqual(usage.window, 258_400)
        XCTAssertEqual(usage.percent, 7)
        XCTAssertEqual(usage.label, "7% of context · 17379 / 258400")
    }

    /// A session rollout file wraps the identical payload in an `event_msg` envelope, and the same reading has
    /// to come out of it: one shape is what a background run sees, the other is what a terminal session leaves
    /// on disk.
    func testCodexReadsThePayloadWrappedShapeIdentically() {
        XCTAssertEqual(ContextUsage.codex(line: Self.codexWrapped), ContextUsage.codex(line: Self.codexBare))
        XCTAssertEqual(ContextUsage.codex(line: Self.codexWrapped)?.percent, 7)
    }

    /// The run's lifetime spend can exceed the window many times over, so it is not the numerator.
    func testCodexUsesTheLastTurnRatherThanTheLifetimeTotal() throws {
        let usage = try XCTUnwrap(ContextUsage.codex(line: Self.codexBare))
        XCTAssertNotEqual(usage.used, 9_294_798)
    }

    /// A window of zero divides by zero and a missing one has nothing to divide by. Both mean "no percentage",
    /// never a crash and never a made-up figure.
    func testAZeroOrMissingWindowYieldsNoPercentage() throws {
        let zero = #"{"type":"token_count","info":{"last_token_usage":{"total_tokens":40},"model_context_window":0}}"#
        let zeroUsage = try XCTUnwrap(ContextUsage.codex(line: zero))
        XCTAssertNil(zeroUsage.percent)
        XCTAssertEqual(zeroUsage.label, "40 tokens")
        let missing = #"{"type":"token_count","info":{"last_token_usage":{"total_tokens":40}}}"#
        let missingUsage = try XCTUnwrap(ContextUsage.codex(line: missing))
        XCTAssertNil(missingUsage.window)
        XCTAssertNil(missingUsage.percent)
    }

    func testCodexReportingNoInfoIsNoReading() {
        XCTAssertNil(ContextUsage.codex(line: #"{"type":"token_count","info":null}"#))
        XCTAssertNil(ContextUsage.codex(line: #"{"type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#))
    }

    func testThePercentageRoundsRatherThanTruncating() {
        XCTAssertEqual(ContextUsage(used: 129_200, window: 258_400).percent, 50)
        XCTAssertEqual(ContextUsage(used: 3, window: 200).percent, 2)
    }

    static let codexBare = #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":16861,"cached_input_tokens":4992,"cache_write_input_tokens":0,"output_tokens":518,"reasoning_output_tokens":217,"total_tokens":9294798},"last_token_usage":{"input_tokens":16861,"cached_input_tokens":4992,"cache_write_input_tokens":0,"output_tokens":518,"reasoning_output_tokens":217,"total_tokens":17379},"model_context_window":258400}}"#
    /// A rollout file's line is that same event inside an envelope, built from it here so the two fixtures
    /// cannot drift apart.
    static let codexWrapped = #"{"timestamp":"2026-09-13T22:23:13.109Z","ordinal":629,"type":"event_msg","payload":"# + codexBare + "}"
}

/// The reading has to reach a background run without costing it a line of its log.
final class JobStreamUsageTests: XCTestCase {
    /// An assistant message carries both its text and its usage. The event stays the line — losing log output
    /// to gain a number would be a bad trade — and the reading is taken beside it.
    func testAUsageBearingAssistantLineStillLogsItsText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading the door"}],"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":97}}}"#
        XCTAssertEqual(JobStream.event(from: line), .line("Reading the door"))
        XCTAssertEqual(JobStream.usage(from: line), ContextUsage(used: 100))
    }

    /// A message with nothing to say but its usage has no line to lose, so the reading is the event itself.
    func testAnAssistantMessageWithOnlyUsageBecomesAReading() {
        let line = #"{"type":"assistant","message":{"content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":9}}}"#
        XCTAssertEqual(JobStream.event(from: line), .usage(ContextUsage(used: 10)))
    }

    func testCodexTokenCountIsAReading() {
        XCTAssertEqual(JobStream.event(from: ContextUsageTests.codexBare), .usage(ContextUsage(used: 17_379, window: 258_400)))
        XCTAssertEqual(JobStream.usage(from: ContextUsageTests.codexWrapped), ContextUsage(used: 17_379, window: 258_400))
    }

    /// The result event still ends the run; its reading is read separately, so neither displaces the other.
    func testAResultStillEndsTheRunAndStillReportsItsUsage() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"Survey written","usage":{"input_tokens":3,"cache_creation_input_tokens":7,"cache_read_input_tokens":10,"output_tokens":50}}"#
        XCTAssertEqual(JobStream.event(from: line), .ended(text: "Survey written", question: nil))
        XCTAssertEqual(JobStream.usage(from: line), ContextUsage(used: 20))
    }

    /// The events that were there before are unchanged, including the lines that are no reading at all.
    func testTheExistingEventsAreUntouched() {
        XCTAssertEqual(JobStream.event(from: #"{"type":"system","subtype":"init","session_id":"abc-123"}"#), .session("abc-123"))
        XCTAssertNil(JobStream.usage(from: #"{"type":"system","subtype":"init","session_id":"abc-123"}"#))
        XCTAssertEqual(JobStream.event(from: "warning: transcript saving is off"), .line("warning: transcript saving is off"))
        XCTAssertNil(JobStream.event(from: #"{"type":"stream_event","delta":{}}"#))
    }
}

@MainActor
final class JobRegistryUsageTests: XCTestCase {
    private final class Spawner: JobSpawner {
        private var lines: [String: @MainActor (String) -> Void] = [:]

        func spawn(id: String, launch: JobLaunch, directory: String,
                   onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) {
            lines[id] = onLine
        }

        func stop(id: String) {}
        @MainActor func emit(_ line: String, to id: String) { lines[id]?(line) }
    }

    /// The run keeps the newest reading, not a total: each event states what is in context now, so adding them
    /// up would climb past any window within a few turns.
    func testTheRunKeepsTheNewestReadingAndItsLog() throws {
        let spawner = Spawner()
        let jobs = JobRegistry(spawner: spawner, home: "/Users/test")
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        XCTAssertNil(jobs.job(id)?.usage, "a run reports nothing until its agent does")
        spawner.emit(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":90}}}"#, to: id)
        XCTAssertEqual(jobs.job(id)?.usage, ContextUsage(used: 100))
        XCTAssertEqual(jobs.job(id)?.log, ["Reading"], "the reading must not cost the run its line")
        spawner.emit(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Writing"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":190}}}"#, to: id)
        XCTAssertEqual(jobs.job(id)?.usage, ContextUsage(used: 200))
        XCTAssertEqual(jobs.job(id)?.log, ["Reading", "Writing"])
    }
}
