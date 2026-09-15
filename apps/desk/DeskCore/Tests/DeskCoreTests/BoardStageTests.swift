import Foundation
import XCTest
@testable import DeskCore

final class BoardStageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWritingAndReadingRoundTrips() {
        let stages = BoardStages(stages: ["42": .readyForDev, "local:c1-callback": .queued, "7": .inProgress])
        stages.write(projectRoot: root)
        XCTAssertEqual(BoardStages.read(projectRoot: root), stages)
        XCTAssertEqual(BoardStages.url(in: root).path, root.appendingPathComponent(".devdesk/board.json").path)
    }

    /// A missing file is "no stages": every card falls back to git and the milestone.
    func testAMissingFileReadsAsEmpty() {
        XCTAssertEqual(BoardStages.read(projectRoot: root), BoardStages())
    }

    /// And so is a corrupt one — a half-written file must not invent a stage for anything.
    func testACorruptFileReadsAsEmpty() throws {
        let url = BoardStages.url(in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(BoardStages.read(projectRoot: root), BoardStages())
    }

    /// Nil clears: a card back in Backlog has no entry, not a "backlog" stage.
    func testSettingNilClearsTheEntry() {
        let stages = BoardStages(stages: ["42": .readyForDev, "7": .queued])
        XCTAssertEqual(stages.setting(nil, for: "42").stages, ["7": .queued])
        XCTAssertEqual(stages.setting(.inProgress, for: "42").stages, ["42": .inProgress, "7": .queued])
        // Clearing what is not there is a no-op, not an error.
        XCTAssertEqual(stages.setting(nil, for: "999"), stages)
    }
}
