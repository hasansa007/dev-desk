import Foundation
import XCTest
@testable import DeskCore

final class ProjectRunPlanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var fileURL: URL { ProjectRunFile.url(in: root) }

    private func writeFile(_ text: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Reading

    func testAMissingFileIsAnEmptyPlanAndNotAnError() {
        let read = ProjectRunFile.read(projectRoot: root)
        XCTAssertEqual(read, .missing)
        XCTAssertEqual(read.plan, .empty)
        XCTAssertNil(read.error)
    }

    func testTheDocumentedShapeDecodes() throws {
        try writeFile("""
        {
          "version": 1,
          "setup": ["cd web && npm install"],
          "configurations": [
            { "id": "web-dev", "name": "Web dev", "commands": ["cd web && npm run dev"], "stop": [], "isDefault": true }
          ]
        }
        """)
        let plan = try XCTUnwrap(ProjectRunFile.read(projectRoot: root).plan)
        XCTAssertEqual(plan.setup, ["cd web && npm install"])
        XCTAssertEqual(plan.configurations.count, 1)
        XCTAssertEqual(plan.configurations[0].id, "web-dev")
        XCTAssertEqual(plan.configurations[0].name, "Web dev")
        XCTAssertEqual(plan.configurations[0].commands, ["cd web && npm run dev"])
        XCTAssertTrue(plan.configurations[0].isDefault)
    }

    /// A hand-written file leaves keys out and adds ones the app has never heard of; neither is a reason to refuse it.
    func testMissingAndUnknownKeysAreTolerated() throws {
        try writeFile(#"{ "configurations": [ { "id": "a", "name": "A", "commands": ["make"], "later": true } ], "extra": 1 }"#)
        let plan = ProjectRunFile.read(projectRoot: root).plan
        XCTAssertEqual(plan.setup, [])
        XCTAssertEqual(plan.configurations[0].stop, [])
        XCTAssertTrue(plan.configurations[0].isDefault, "the only configuration is the default even when nothing marks it")
    }

    /// The reason is what the pane shows instead of silently replacing the file with an empty plan.
    func testMalformedJSONIsReportedAndTheFileIsLeftAlone() throws {
        let broken = #"{ "configurations": [ { "id": "a", "name": "A", "commands": "make" } ] }"#
        try writeFile(broken)
        let read = ProjectRunFile.read(projectRoot: root)
        XCTAssertEqual(read.plan, .empty)
        let reason = try XCTUnwrap(read.error)
        XCTAssertTrue(reason.contains(ProjectRunFile.relativePath), reason)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), broken)
    }

    func testNotJSONAtAllIsReported() throws {
        try writeFile("this is not json")
        XCTAssertNotNil(ProjectRunFile.read(projectRoot: root).error)
    }

    /// The read goes through `SafeFile`: a link to a file outside the project is refused, not followed.
    func testASymlinkedFileIsRefused() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try #"{ "configurations": [] }"#.write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: outside)
        let read = ProjectRunFile.read(projectRoot: root)
        XCTAssertNotEqual(read, .missing)
        XCTAssertNotNil(read.error)
    }

    func testAnOversizedFileIsRefused() throws {
        try writeFile("{\"setup\": [\"" + String(repeating: "x", count: ProjectRunFile.maxBytes + 1) + "\"]}")
        let reason = try XCTUnwrap(ProjectRunFile.read(projectRoot: root).error)
        XCTAssertTrue(reason.contains("larger"), reason)
    }

    // MARK: - Normalising

    func testBlankRowsAreDroppedOnRead() {
        let read = ProjectRunFile.parse(#"{ "setup": ["  ", "npm install", ""], "configurations": [ { "id": "a", "name": " A ", "commands": ["", " npm start "], "stop": ["\n"] } ] }"#)
        let plan = read.plan
        XCTAssertEqual(plan.setup, ["npm install"])
        XCTAssertEqual(plan.configurations[0].name, "A")
        XCTAssertEqual(plan.configurations[0].commands, ["npm start"])
        XCTAssertEqual(plan.configurations[0].stop, [])
    }

    func testTheFirstConfigurationIsTheDefaultWhenNoneIsMarked() {
        let plan = ProjectRunPlan(configurations: [
            ProjectRunConfiguration(id: "a", name: "A", commands: ["a"]),
            ProjectRunConfiguration(id: "b", name: "B", commands: ["b"]),
        ])
        XCTAssertEqual(plan.defaultConfiguration?.id, "a")
        XCTAssertEqual(plan.normalised().configurations.map(\.isDefault), [true, false])
    }

    func testTheFirstMarkedDefaultWinsAndSavingLeavesExactlyOne() {
        let plan = ProjectRunPlan(configurations: [
            ProjectRunConfiguration(id: "a", name: "A", commands: ["a"]),
            ProjectRunConfiguration(id: "b", name: "B", commands: ["b"], isDefault: true),
            ProjectRunConfiguration(id: "c", name: "C", commands: ["c"], isDefault: true),
        ])
        XCTAssertEqual(plan.defaultConfiguration?.id, "b")
        XCTAssertEqual(plan.normalised().configurations.map(\.isDefault), [false, true, false])
    }

    func testAnEmptyPlanHasNoDefault() {
        XCTAssertNil(ProjectRunPlan.empty.defaultConfiguration)
        XCTAssertTrue(ProjectRunPlan.empty.isEmpty)
    }

    // MARK: - Composition

    func testRowsJoinWithAndSoTheShellStopsAtTheFirstFailure() {
        XCTAssertEqual(ProjectRunPlan.shellLine(rows: [" cd web ", "npm run dev"]), "cd web && npm run dev")
        XCTAssertNil(ProjectRunPlan.shellLine(rows: []))
        XCTAssertNil(ProjectRunPlan.shellLine(rows: ["", "   "]))
    }

    func testSetupRowsLeadWhenIncluded() {
        let plan = ProjectRunPlan(setup: ["npm install"],
                                  configurations: [ProjectRunConfiguration(id: "a", name: "A", commands: ["npm run dev"], stop: ["npm run stop"])])
        let configuration = plan.configurations[0]
        XCTAssertEqual(plan.shellLine(configuration: configuration, includingSetup: true), "npm install && npm run dev")
        XCTAssertEqual(plan.shellLine(configuration: configuration, includingSetup: false), "npm run dev")
        XCTAssertEqual(plan.stopLine(configuration: configuration), "npm run stop")
    }

    func testAConfigurationWithNoRowsHasNothingToRun() {
        let plan = ProjectRunPlan(configurations: [ProjectRunConfiguration(id: "a", name: "A")])
        XCTAssertNil(plan.shellLine(configuration: plan.configurations[0], includingSetup: false))
        XCTAssertNil(plan.stopLine(configuration: plan.configurations[0]))
    }

    // MARK: - Writing

    func testWritingCreatesTheFolderAndRoundTrips() throws {
        let plan = ProjectRunPlan(setup: ["cd web && npm install"],
                                  configurations: [ProjectRunConfiguration(id: "web-dev", name: "Web dev",
                                                                           commands: ["cd web && npm run dev"], isDefault: true)])
        try ProjectRunFile.write(plan, projectRoot: root)
        XCTAssertEqual(ProjectRunFile.read(projectRoot: root), .plan(plan))
    }

    /// Sorted keys and a version, so the committed file diffs by what changed and a later reader can tell its age.
    func testTheFileIsPrettyPrintedWithSortedKeysAndAVersion() throws {
        let plan = ProjectRunPlan(configurations: [ProjectRunConfiguration(id: "a", name: "A", commands: ["make"])])
        let text = String(decoding: try ProjectRunFile.encode(plan), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\n  \"configurations\""), text)
        XCTAssertTrue(text.contains("\"version\" : 1"), text)
        XCTAssertTrue(text.hasSuffix("}\n"), "ends with a newline, as a committed text file should")
        let keys = ["\"commands\"", "\"id\"", "\"isDefault\"", "\"name\"", "\"stop\""]
        let positions = keys.map { text.range(of: $0)!.lowerBound }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testSavingNormalisesWhatItWrites() throws {
        let plan = ProjectRunPlan(setup: [" ", "npm install "],
                                  configurations: [ProjectRunConfiguration(id: "a", name: "A", commands: ["a"], isDefault: true),
                                                   ProjectRunConfiguration(id: "b", name: "B", commands: [""], isDefault: true)])
        try ProjectRunFile.write(plan, projectRoot: root)
        let written = ProjectRunFile.read(projectRoot: root).plan
        XCTAssertEqual(written.setup, ["npm install"])
        XCTAssertEqual(written.configurations.map(\.isDefault), [true, false])
        XCTAssertEqual(written.configurations[1].commands, [])
    }

    func testGeneratedIDsAreShortAndDistinct() {
        let ids = (0..<50).map { _ in ProjectRunConfiguration.newID() }
        XCTAssertEqual(Set(ids).count, 50)
        XCTAssertTrue(ids.allSatisfy { $0.count == 8 && $0 == $0.lowercased() })
    }
}
