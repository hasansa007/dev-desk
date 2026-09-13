import Foundation
import XCTest
@testable import DeskCore

final class JobStreamTests: XCTestCase {
    func testTheSessionIdIsReadFromTheInitLine() {
        // Codex reports its own id; claude is told one. Either way `--resume` needs it back.
        let event = JobStream.event(from: #"{"type":"system","subtype":"init","session_id":"abc-123"}"#)
        XCTAssertEqual(event, .session("abc-123"))
    }

    func testAssistantTextBecomesALine() {
        let event = JobStream.event(from: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading the door"}]}}"#)
        XCTAssertEqual(event, .line("Reading the door"))
    }

    func testAToolUseSaysWhatItWasPointedAt() {
        let event = JobStream.event(from: #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#)
        XCTAssertEqual(event, .line("· Bash ls"))
        let read = JobStream.event(from: #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"Services/ReminderService.swift"}}]}}"#)
        XCTAssertEqual(read, .line("· Read Services/ReminderService.swift"))
    }

    /// An agent writes a description for a shell command because the command is not the readable version.
    func testADescribedCommandShowsItsDescription() {
        let event = JobStream.event(from: #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh issue create --title x","description":"File the issue"}}]}}"#)
        XCTAssertEqual(event, .line("· Bash File the issue"))
    }

    /// A row is a row: a heredoc would otherwise be the whole log.
    func testALongArgumentIsCutToOneLine() {
        let command = String(repeating: "a", count: 300) + #"\n"# + "second line"
        let json = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"\(command)\"}}]}}"
        guard case .line(let text)? = JobStream.event(from: json) else { return XCTFail("expected a line") }
        XCTAssertEqual(text.count, 127, text)          // "· Bash " + 120
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertFalse(text.contains("\n"))
    }

    /// A loop is a failure repeating, and it is invisible if failures are not shown.
    func testAFailedToolResultIsShown() {
        let event = JobStream.event(from: #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"GraphQL: Could not resolve to a Repository"}]}}"#)
        XCTAssertEqual(event, .line("! GraphQL: Could not resolve to a Repository"))
    }

    func testASuccessfulToolResultIsNotNoise() {
        XCTAssertNil(JobStream.event(from: #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":false,"content":"ok"}]}}"#))
    }

    func testASuccessfulResultEndsWithoutAQuestion() {
        let event = JobStream.event(from: #"{"type":"result","subtype":"success","is_error":false,"result":"Survey written"}"#)
        XCTAssertEqual(event, .ended(text: "Survey written", question: nil))
    }

    /// A headless run has no terminal to prompt in, so needing an answer shows up as its ending.
    func testAnErrorResultEndsWithAQuestionToAnswer() {
        let event = JobStream.event(from: #"{"type":"result","subtype":"error_max_turns","is_error":true,"result":"Needs permission to push"}"#)
        XCTAssertEqual(event, .ended(text: "Needs permission to push", question: "Needs permission to push"))
    }

    /// Only a stop-to-ask is a question. Anything else that failed simply failed.
    func testAFailureIsNotAQuestion() {
        let event = JobStream.event(from: #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Credit balance too low"}"#)
        XCTAssertEqual(event, .ended(text: "Credit balance too low", question: nil))
    }

    /// Agents print plain notices between JSON lines; dropping them hides why a run stalled.
    func testANonJsonNoticeIsKeptAsALine() {
        XCTAssertEqual(JobStream.event(from: "warning: transcript saving is off"), .line("warning: transcript saving is off"))
    }

    func testBlankAndUnknownLinesAreIgnored() {
        XCTAssertNil(JobStream.event(from: "   "))
        XCTAssertNil(JobStream.event(from: #"{"type":"stream_event","delta":{}}"#))
    }
}

@MainActor
final class JobRegistryTests: XCTestCase {
    private final class FakeSpawner: JobSpawner {
        var launched: [(id: String, launch: JobLaunch)] = []
        var stopped: [String] = []
        private var lines: [String: @MainActor (String) -> Void] = [:]
        private var exits: [String: @MainActor (Int32) -> Void] = [:]

        func spawn(id: String, launch: JobLaunch, directory: String,
                   onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) {
            launched.append((id, launch))
            lines[id] = onLine
            exits[id] = onExit
        }

        func stop(id: String) { stopped.append(id) }
        @MainActor func emit(_ line: String, to id: String) { lines[id]?(line) }
        @MainActor func exit(_ status: Int32, of id: String) { exits[id]?(status) }
    }

    private func registry() -> (JobRegistry, FakeSpawner) {
        let spawner = FakeSpawner()
        return (JobRegistry(spawner: spawner, home: "/Users/test"), spawner)
    }

    func testStartingAJobSpawnsTheHeadlessArgv() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        XCTAssertEqual(spawner.launched.count, 1)
        XCTAssertEqual(spawner.launched[0].launch.executable, "claude")
        XCTAssertTrue(spawner.launched[0].launch.arguments.contains("--output-format"))
        XCTAssertEqual(jobs.job(id)?.state, .starting)
        XCTAssertEqual(jobs.liveCount, 1)
    }

    func testAnAgentWithNoVerifiedInvocationStartsNothing() {
        let (jobs, spawner) = registry()
        XCTAssertNil(jobs.start(door: "survey", title: "Survey", agent: "Gemini", permission: .readOnly, directory: "/repo"))
        XCTAssertTrue(spawner.launched.isEmpty, "a guessed invocation is worse than none")
        XCTAssertTrue(jobs.jobs.isEmpty)
    }

    func testTheLogStreamsAndTheSessionIdIsLearned() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Codex",
                                          permission: .readOnly, directory: "/repo"))
        spawner.emit(#"{"type":"system","subtype":"init","session_id":"sess-9"}"#, to: id)
        spawner.emit(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading"}]}}"#, to: id)
        XCTAssertEqual(jobs.job(id)?.sessionID, "sess-9")
        XCTAssertEqual(jobs.job(id)?.state, .running)
        XCTAssertEqual(jobs.job(id)?.log, ["Reading"])
    }

    func testARunThatEndsOnAQuestionWaitsRatherThanFinishing() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        spawner.emit(#"{"type":"result","subtype":"error_max_turns","is_error":true,"result":"Push?"}"#, to: id)
        XCTAssertEqual(jobs.job(id)?.state, .asking("Push?"))
        // The process exits right after; that exit must not overwrite the question with "finished".
        spawner.exit(0, of: id)
        XCTAssertEqual(jobs.job(id)?.state, .asking("Push?"))
    }

    func testAnsweringResumesTheSameSession() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        let sessionID = jobs.job(id)?.sessionID
        XCTAssertNotNil(sessionID)
        spawner.emit(#"{"type":"result","subtype":"error_permission","is_error":true,"result":"Push?"}"#, to: id)
        jobs.answer("yes, push", to: id)
        XCTAssertEqual(spawner.launched.count, 2)
        let resumed = try XCTUnwrap(spawner.launched.last).launch.arguments
        XCTAssertTrue(resumed.contains("--resume"))
        XCTAssertTrue(resumed.contains(sessionID ?? "—"))
        XCTAssertTrue(resumed.contains("yes, push"))
        XCTAssertEqual(jobs.job(id)?.state, .starting)
    }

    /// An exhausted balance or a bad key is a failure, not a question. Presenting it as one leaves the row
    /// waiting forever: an asking job ignores its own exit, and answering resumes a session that fails the same.
    func testARealFailureEndsRatherThanAsking() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        spawner.emit(#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Credit balance too low"}"#, to: id)
        XCTAssertEqual(jobs.job(id)?.state, .ended(text: "Credit balance too low", failed: false))
        XCTAssertFalse(jobs.job(id)?.state.isLive ?? true)
    }

    /// Resuming without the grant drops a headless run back to prompting, and a run with no terminal to prompt
    /// in stalls on its first tool call and asks again — a loop the developer cannot break.
    func testAnsweringCarriesTheGrantTheRunStartedWith() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .everything, directory: "/repo"))
        spawner.emit(#"{"type":"result","subtype":"error_permission","is_error":true,"result":"Push?"}"#, to: id)
        jobs.answer("go", to: id)
        let resumed = try XCTUnwrap(spawner.launched.last).launch.arguments
        XCTAssertTrue(resumed.contains("--dangerously-skip-permissions"), "the grant must survive the answer")
    }

    /// The mode is the run's, not the preference's: a delegate run answered after the preference changed must
    /// still resume with its worker, or it has nothing to hand the step to. Claude's `--agents` needs no file,
    /// so it is the one that shows the stored mode travelled with the answer.
    func testAnsweringADelegateRunCarriesTheDelegateFlags() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .writeInRepo, directory: "/repo", mode: .delegate))
        XCTAssertTrue(try XCTUnwrap(spawner.launched.first).launch.arguments.contains("--agents"),
                      "a delegate run starts with its worker")
        spawner.emit(#"{"type":"result","subtype":"error_permission","is_error":true,"result":"Push?"}"#, to: id)
        jobs.answer("go", to: id)
        let resumed = try XCTUnwrap(spawner.launched.last).launch.arguments
        XCTAssertTrue(resumed.contains("--agents"), "the mode must survive the answer, not follow the preference")
    }

    /// Re-spawning under the same id without stopping the old process lets its termination handler fire against
    /// the new one — marking a live run finished, and leaving it unstoppable.
    func testAnsweringStopsThePreviousProcessFirst() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        spawner.emit(#"{"type":"result","subtype":"error_permission","is_error":true,"result":"Push?"}"#, to: id)
        jobs.answer("go", to: id)
        XCTAssertEqual(spawner.stopped, [id])
    }

    func testOneBackgroundRunPerDoor() throws {
        let (jobs, _) = registry()
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                     permission: .readOnly, directory: "/repo"))
        XCTAssertTrue(jobs.hasLiveJob(door: "survey", in: "/repo"))
        XCTAssertFalse(jobs.hasLiveJob(door: "ideation", in: "/repo"))
        XCTAssertFalse(jobs.hasLiveJob(door: "survey", in: "/other"),
                       "one run per door is per project — another repo's window is not running this")
    }

    /// Survey is blocked by the half of the report it writes, not by its door: the two halves are written by
    /// different runs and belong side by side.
    func testTwoSurveyScopesRunSideBySideAndTheSameScopeDoesNot() throws {
        let (jobs, _) = registry()
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey · Defects", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo", scope: .defects))
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .defects, in: "/repo"), "the same half twice would overwrite itself")
        XCTAssertFalse(jobs.hasLiveSurvey(scope: .architecture, in: "/repo"),
                       "the other half writes somewhere else and may start")
        XCTAssertFalse(jobs.hasLiveSurvey(scope: .defects, in: "/other"), "still per project")
    }

    /// `both` occupies the whole report, so it conflicts with everything — in either direction.
    func testBothConflictsWithEveryScope() throws {
        let (jobs, _) = registry()
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo", scope: .both))
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .defects, in: "/repo"))
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .architecture, in: "/repo"))
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .both, in: "/repo"))
    }

    func testAHalfEachBlocksAWholeSurvey() throws {
        let (jobs, _) = registry()
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey · Defects", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo", scope: .defects))
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey · Architecture", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo", scope: .architecture))
        XCTAssertEqual(jobs.liveCount, 2, "the two halves run together")
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .both, in: "/repo"), "a whole survey would write over both of them")
    }

    /// A finished run blocks nothing, and a run recorded without a scope is read as the whole report rather
    /// than as something a second survey may quietly write over.
    func testAScopeIsOnlyBlockedWhileItsRunIsLive() throws {
        let (jobs, _) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .writeInRepo, directory: "/repo"))
        XCTAssertTrue(jobs.hasLiveSurvey(scope: .architecture, in: "/repo"), "no scope recorded means both halves")
        jobs.stop(id)
        XCTAssertFalse(jobs.hasLiveSurvey(scope: .both, in: "/repo"))
    }

    /// Roadmap and create-issue have no halves: their rule is the door-wide one, and the scope of a survey
    /// beside them changes nothing about it.
    func testOtherDoorsStillBlockByDoorAlone() throws {
        let (jobs, _) = registry()
        _ = try XCTUnwrap(jobs.start(door: "roadmap", title: "Roadmap", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo"))
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey · Defects", agent: "Claude",
                                     permission: .writeInRepo, directory: "/repo", scope: .defects))
        XCTAssertTrue(jobs.hasLiveJob(door: "roadmap", in: "/repo"))
        XCTAssertFalse(jobs.hasLiveSurvey(scope: .architecture, in: "/repo"),
                       "another door's run is not a survey of any scope")
    }

    func testAnsweringAJobThatIsNotAskingDoesNothing() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        jobs.answer("hello", to: id)
        XCTAssertEqual(spawner.launched.count, 1, "a running job is not waiting on anything")
    }

    func testStopEndsItAndTheRowStaysUntilRemoved() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        jobs.stop(id)
        XCTAssertEqual(spawner.stopped, [id])
        XCTAssertEqual(jobs.job(id)?.state, .ended(text: "Stopped", failed: false))
        XCTAssertEqual(jobs.liveCount, 0)
        jobs.remove(id)
        XCTAssertTrue(jobs.jobs.isEmpty)
    }

    func testALiveJobCannotBeRemovedFromTheList() throws {
        let (jobs, _) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        jobs.remove(id)
        XCTAssertEqual(jobs.jobs.count, 1, "removing a row must never orphan its process")
    }

    /// A crash writes no result line. Without this the row pulses forever and the count never comes down.
    func testACrashWithNoResultStillEnds() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        spawner.exit(9, of: id)
        XCTAssertEqual(jobs.job(id)?.state, .ended(text: "Exited with status 9", failed: true))
    }

    func testTheLogIsCappedSoARunThatTalksForeverIsStillARow() throws {
        let (jobs, spawner) = registry()
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .readOnly, directory: "/repo"))
        for i in 1...(BackgroundJob.logLimit + 40) {
            spawner.emit("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"line \(i)\"}]}}", to: id)
        }
        XCTAssertEqual(jobs.job(id)?.log.count, BackgroundJob.logLimit)
        XCTAssertEqual(jobs.job(id)?.log.last, "line \(BackgroundJob.logLimit + 40)")
    }

    /// A journal over a real temporary folder rather than a stub: what is being proved is that a killed app
    /// leaves a record behind on disk, which a stub would only assert had been asked for.
    private func journalled() throws -> (JobRegistry, FakeSpawner, RunJournal, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let journal = RunJournal(projectRoot: root)
        let (jobs, spawner) = registry()
        jobs.journalFor = { $0 == root.path ? journal : nil }
        return (jobs, spawner, journal, root)
    }

    /// The crash case, end to end: a live run is on disk and unclean from its first moment, every change it
    /// makes rewrites it, and only its end takes it away (ADR 0030).
    func testALiveRunIsWrittenDownAndItsEndClearsIt() throws {
        let (jobs, spawner, journal, root) = try journalled()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Codex",
                                          permission: .writeInRepo, directory: root.path, mode: .delegate))
        let started = try XCTUnwrap(journal.recover().first)
        XCTAssertEqual(started.id, id)
        XCTAssertEqual(started.kind, .backgroundRun)
        XCTAssertEqual(started.clean, false, "a record is unclean while it is live — that is what recovery reads")
        XCTAssertEqual(started.stateLabel, "Starting")
        XCTAssertEqual(started.permission, RunPermission.writeInRepo.rawValue)
        XCTAssertEqual(started.mode, RunMode.delegate.rawValue)

        spawner.emit(#"{"type":"system","subtype":"init","session_id":"sess-9"}"#, to: id)
        spawner.emit(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading the door"}]}}"#, to: id)
        let running = try XCTUnwrap(journal.recover().first)
        XCTAssertEqual(journal.all().count, 1, "the same run stays one record")
        XCTAssertEqual(running.stateLabel, "Running in the background")
        XCTAssertEqual(running.sessionID, "sess-9", "without the id there is nothing to resume")
        XCTAssertEqual(running.logTail, ["Reading the door"])

        spawner.emit(#"{"type":"result","subtype":"success","is_error":false,"result":"Survey written"}"#, to: id)
        XCTAssertTrue(journal.all().isEmpty, "a finished run is history, not something to offer to continue")
    }

    /// Quitting ends the run the same way a kill does, but on the app's terms. Without the clean mark every
    /// ordinary quit would reappear as a crash to recover from.
    func testAGracefulQuitMarksTheRecordCleanInsteadOfLeavingItLookingLikeACrash() throws {
        let (jobs, _, journal, root) = try journalled()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                     permission: .readOnly, directory: root.path))
        jobs.markAllClean()
        XCTAssertTrue(journal.recover().isEmpty)
        XCTAssertEqual(journal.all().map(\.clean), [true])
    }

    /// The one thing recovery can honestly do when the session id was captured: continue that session, under
    /// the grant the dead run held, and take its record away so it is not offered twice.
    func testResumingFromARecordContinuesTheSessionAndClearsTheRecord() throws {
        let (jobs, spawner, journal, root) = try journalled()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try XCTUnwrap(jobs.start(door: "survey", title: "Survey", agent: "Claude",
                                          permission: .everything, directory: root.path))
        let record = try XCTUnwrap(journal.recover().first)
        // The run itself is gone; this stands in for the app it died with.
        jobs.stop(id)
        let resumed = try XCTUnwrap(jobs.resumeFromRecord(record))
        let launch = try XCTUnwrap(spawner.launched.last).launch
        XCTAssertTrue(launch.arguments.contains("--resume"))
        XCTAssertTrue(launch.arguments.contains(try XCTUnwrap(record.sessionID)))
        XCTAssertTrue(launch.arguments.contains("--dangerously-skip-permissions"), "the dead run's grant, not today's default")
        XCTAssertEqual(jobs.job(resumed)?.title, "Survey")
        XCTAssertEqual(journal.recover().map(\.id), [resumed], "the old record is gone; the new run has its own")
    }

    func testARecordWithNoSessionIdHasNothingToResume() throws {
        let (jobs, _, _, root) = try journalled()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = JournalRecord(id: "job:survey:dead", kind: .backgroundRun, title: "Survey", agent: "Claude",
                                   directory: root.path, stateLabel: "Running in the background")
        XCTAssertNil(jobs.resumeFromRecord(record))
        XCTAssertTrue(jobs.jobs.isEmpty, "a resume that cannot continue the session must start nothing")
    }
}
