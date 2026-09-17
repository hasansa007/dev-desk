import XCTest
@testable import DeskCore

final class PipelineStateTests: XCTestCase {
    func testPhaseNineIsDoneDoneCurrentPending() {
        let progress = PipelineState(phase: 9).progress
        XCTAssertEqual(progress.stages, [
            PipelineStage("Investigated", .done), PipelineStage("Planned", .done),
            PipelineStage("Implementing", .current), PipelineStage("Verified", .pending),
        ])
        XCTAssertEqual(progress.note, "Advisory — read from .dev state; git wins any disagreement.")
    }

    func testPhaseThreeIsCurrentThenPending() {
        XCTAssertEqual(PipelineState(phase: 3).progress.stages.map(\.state), [.current, .pending, .pending, .pending])
    }

    func testPhaseFourteenAndAboveIsAllDone() {
        XCTAssertEqual(PipelineState(phase: 14).progress.stages.map(\.state), [.done, .done, .done, .done])
        XCTAssertEqual(PipelineState(phase: 16).progress.stages.map(\.state), [.done, .done, .done, .done])
    }

    func testSlugReplacesEverythingOutsideTheSafeSet() {
        XCTAssertEqual(PipelineState.slug("feat/a b"), "feat-a-b")
        XCTAssertEqual(PipelineState.slug("fix/42_x.y-z"), "fix-42_x.y-z")
        XCTAssertEqual(PipelineState.slug("café"), "caf-")
    }

    func testParseReadsPhaseGroupTierAndCompletedPhases() {
        let json = #"{"branch":"gh-12-x","phase":9,"phase_group":"coding","tier":"standard","phases_completed":[1,2,3],"attempts":[]}"#
        XCTAssertEqual(PipelineState.parse(Data(json.utf8)),
                       PipelineState(phase: 9, phaseGroup: "coding", tier: "standard", phasesCompleted: [1, 2, 3]))
    }

    func testMissingPhaseOrUnparsableFileIsNil() {
        XCTAssertNil(PipelineState.parse(Data(#"{"phase":null,"tier":null}"#.utf8)))
        XCTAssertNil(PipelineState.parse(Data(#"{"phase_group":"coding"}"#.utf8)))
        XCTAssertNil(PipelineState.parse(Data("not json".utf8)))
    }

    func testCardNoteAndEvidenceCheck() {
        let untiered = PipelineState(phase: 9, phaseGroup: "coding")
        XCTAssertEqual(untiered.cardNote, "Implementing · phase 9 done")
        XCTAssertEqual(untiered.check, CheckResult(id: "pipeline", name: "Pipeline state", outcome: .passed,
                                                   outcomeLabel: "phase 9 · no tier", revisionLabel: "advisory"))
        XCTAssertEqual(PipelineState(phase: 11, tier: "standard").check.outcomeLabel, "phase 11 · standard")
        XCTAssertEqual(PipelineState(phase: 2).cardNote, "Planning · phase 2 done")
        XCTAssertEqual(PipelineState(phase: 13).cardNote, "Opening the PR · phase 13 done")
    }

    func testTaskStateFileNames() {
        XCTAssertEqual(PipelineState.issueNumber(fileName: "issue-778.json"), 778)
        XCTAssertNil(PipelineState.issueNumber(fileName: "gh-778-x.json"))
        XCTAssertNil(PipelineState.issueNumber(fileName: "issue-x.json"))
        XCTAssertEqual(PipelineState.localID(fileName: "local-c1-callback.json"), "c1-callback")
        XCTAssertNil(PipelineState.localID(fileName: "local-.json"))
    }
}
