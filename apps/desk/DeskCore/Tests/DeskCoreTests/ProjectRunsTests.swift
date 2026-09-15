import Foundation
import XCTest
@testable import DeskCore

@MainActor
final class ProjectRunsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRuns(root: URL? = nil) -> ProjectRuns {
        let projectRoot = root ?? self.root
        return ProjectRuns(projectRoot: projectRoot, sessions: ShellSessions(projectRoot: projectRoot, runner: FakeRunner()))
    }

    private func writePlan(setup: [String] = [], _ configurations: [ProjectRunConfiguration]) throws {
        try ProjectRunFile.write(ProjectRunPlan(setup: setup, configurations: configurations), projectRoot: root)
    }

    private var web: ProjectRunConfiguration {
        ProjectRunConfiguration(id: "web-dev", name: "Web dev", commands: ["cd web && npm run dev"], stop: ["npm run stop"])
    }

    private var api: ProjectRunConfiguration {
        ProjectRunConfiguration(id: "api", name: "API", commands: ["make api"], isDefault: true)
    }

    // MARK: - The plan

    func testASampleHasAnEmptyPlanAndNothingToRun() {
        let runs = makeRuns(root: URL(fileURLWithPath: "/nonexistent/sample", isDirectory: true))
        let sample = ProjectRuns(projectRoot: nil, sessions: ShellSessions(projectRoot: nil, runner: FakeRunner()))
        XCTAssertEqual(sample.plan, .empty)
        XCTAssertFalse(sample.canRun)
        XCTAssertNil(sample.prepare(folderPath: "/anywhere"))
        XCTAssertFalse(sample.needsSetup(in: "/anywhere"))
        // A local project with no file is the same empty plan, without an error.
        XCTAssertEqual(runs.plan, .empty)
        XCTAssertNil(runs.readError)
        XCTAssertNil(runs.prepare(folderPath: root.path))
    }

    func testTheFileIsReadAtCreationAndOnReload() throws {
        try writePlan([web])
        let runs = makeRuns()
        XCTAssertEqual(runs.plan.configurations.map(\.id), ["web-dev"])
        try writePlan([web, api])
        XCTAssertEqual(runs.plan.configurations.count, 1, "nothing is re-read until asked")
        runs.reload()
        XCTAssertEqual(runs.plan.configurations.map(\.id), ["web-dev", "api"])
    }

    func testAMalformedFileLeavesAnEmptyPlanWithTheReasonAndIsNotRewritten() throws {
        let url = ProjectRunFile.url(in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let runs = makeRuns()
        XCTAssertEqual(runs.plan, .empty)
        XCTAssertNotNil(runs.readError)
        XCTAssertFalse(runs.canRun)
        XCTAssertNil(runs.prepare(folderPath: root.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
    }

    /// The pane's "replace the file" path: an explicit save is the one thing allowed to overwrite a broken file.
    func testSavingReplacesABrokenFileAndClearsTheReason() throws {
        let url = ProjectRunFile.url(in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let runs = makeRuns()
        try runs.save(ProjectRunPlan(configurations: [web]))
        XCTAssertNil(runs.readError)
        XCTAssertEqual(runs.plan.configurations.map(\.id), ["web-dev"])
        XCTAssertEqual(ProjectRunFile.read(projectRoot: root).plan.configurations.map(\.id), ["web-dev"])
    }

    func testSavingKeepsTheNormalisedPlan() throws {
        let runs = makeRuns()
        var loose = web
        loose.commands = ["", " npm run dev "]
        try runs.save(ProjectRunPlan(configurations: [loose]))
        XCTAssertEqual(runs.plan.configurations[0].commands, ["npm run dev"])
        XCTAssertTrue(runs.plan.configurations[0].isDefault)
        XCTAssertTrue(runs.canRun)
    }

    // MARK: - Launch decisions

    func testTheDefaultConfigurationIsWhatAPlainRunOpens() throws {
        try writePlan([web, api])
        let runs = makeRuns()
        let launch = try XCTUnwrap(runs.prepare(folderPath: root.path))
        XCTAssertEqual(launch.configuration?.id, "api")
        XCTAssertEqual(launch.sessionID, "run:api")
        XCTAssertEqual(launch.title, "Run · API")
        XCTAssertEqual(launch.shellLine, "make api")
        XCTAssertFalse(launch.includesSetup, "a plan with no setup rows never includes them")
    }

    func testANamedConfigurationIsOpenedByID() throws {
        try writePlan([web, api])
        let runs = makeRuns()
        let launch = try XCTUnwrap(runs.prepare(configurationID: "web-dev", folderPath: root.path))
        XCTAssertEqual(launch.sessionID, "run:web-dev")
        XCTAssertEqual(launch.shellLine, "cd web && npm run dev")
        XCTAssertNil(runs.prepare(configurationID: "missing", folderPath: root.path))
    }

    func testSetupIsIncludedOnTheFirstRunInAFolderAndSkippedAfterwards() throws {
        try writePlan(setup: ["npm install"], [web])
        let runs = makeRuns()
        XCTAssertTrue(runs.needsSetup(in: root.path))
        let first = try XCTUnwrap(runs.prepare(folderPath: root.path))
        XCTAssertTrue(first.includesSetup)
        XCTAssertEqual(first.shellLine, "npm install && cd web && npm run dev")
        // Preparing decides; only a dispatch records. A launch that never started must not spend the first run.
        XCTAssertTrue(runs.needsSetup(in: root.path))
        runs.dispatched(first, in: root.path)
        XCTAssertFalse(runs.needsSetup(in: root.path))
        let second = try XCTUnwrap(runs.prepare(folderPath: root.path))
        XCTAssertFalse(second.includesSetup)
        XCTAssertEqual(second.shellLine, "cd web && npm run dev")
        // Another folder — a worktree — has had no setup yet.
        XCTAssertTrue(runs.needsSetup(in: root.path + "-worktree"))
    }

    func testSetupCanAlwaysBeForcedFromTheMenu() throws {
        try writePlan(setup: ["npm install"], [web])
        let runs = makeRuns()
        runs.markSetupStarted(in: root.path)
        let forced = try XCTUnwrap(runs.prepare(intent: .setupAndRun, folderPath: root.path))
        XCTAssertTrue(forced.includesSetup)
        XCTAssertEqual(forced.shellLine, "npm install && cd web && npm run dev")
        let alone = try XCTUnwrap(runs.prepare(intent: .setupOnly, folderPath: root.path))
        XCTAssertEqual(alone.sessionID, ProjectRuns.setupSessionID)
        XCTAssertNil(alone.configuration)
        XCTAssertEqual(alone.shellLine, "npm install")
        XCTAssertEqual(alone.title, "Run · Setup")
    }

    func testSetupOnlyWithNoSetupRowsIsNothingToRun() throws {
        try writePlan([web])
        XCTAssertNil(makeRuns().prepare(intent: .setupOnly, folderPath: root.path))
    }

    // MARK: - The marker

    /// The marker is a map of folder path to the moment setup was dispatched there, and it says only that
    /// much: a folder is recorded whether or not its install finished.
    func testTheMarkerRoundTripsPerFolder() throws {
        try writePlan(setup: ["npm install"], [web])
        let runs = makeRuns()
        let when = Date(timeIntervalSince1970: 1_757_800_000)
        runs.markSetupStarted(in: "/a", at: when)
        runs.markSetupStarted(in: "/b")
        let state = ProjectRunState.read(projectRoot: root)
        XCTAssertEqual(state.setupStarted["/a"], when)
        XCTAssertNotNil(state.setupStarted["/b"])
        XCTAssertFalse(runs.needsSetup(in: "/a"))
        XCTAssertFalse(runs.needsSetup(in: "/b"))
        XCTAssertTrue(runs.needsSetup(in: "/c"))
        let url = ProjectRunState.url(in: root)
        XCTAssertEqual(url.lastPathComponent, "run-state.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnUnreadableMarkerCountsAsNoSetupRecorded() throws {
        try writePlan(setup: ["npm install"], [web])
        let url = ProjectRunState.url(in: root)
        try "garbage".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(makeRuns().needsSetup(in: root.path))
    }

    // MARK: - Sessions

    func testADispatchedRunIsListedWithItsTitleAndForgottenOnlyWhenNotLive() throws {
        try writePlan([web])
        let runs = makeRuns()
        let launch = try XCTUnwrap(runs.prepare(folderPath: root.path))
        runs.dispatched(launch, in: root.path)
        XCTAssertEqual(runs.sessionIDs, ["run:web-dev"])
        XCTAssertEqual(runs.title(sessionID: "run:web-dev"), "Run · Web dev")
        XCTAssertEqual(runs.stopLine(sessionID: "run:web-dev"), "npm run stop")
        // Nothing here has a shell, so the session is not live and the row can be taken off the list.
        XCTAssertNil(runs.liveConfiguration)
        XCTAssertNil(runs.liveSessionID)
        runs.forget(sessionID: "run:web-dev")
        XCTAssertEqual(runs.sessionIDs, [])
        XCTAssertNil(runs.stopLine(sessionID: "run:web-dev"))
    }

    func testSessionIDsCarryTheRunPrefix() {
        XCTAssertEqual(ProjectRuns.sessionID(configurationID: "web-dev"), "run:web-dev")
        XCTAssertTrue(ProjectRuns.isRunSession("run:web-dev"))
        XCTAssertTrue(ProjectRuns.isRunSession(ProjectRuns.setupSessionID))
        XCTAssertFalse(ProjectRuns.isRunSession("term:1"))
        XCTAssertFalse(ProjectRuns.isRunSession("door:dev"))
    }

    func testTheWindowModelOwnsARunsObjectForItsRoot() throws {
        try writePlan([web])
        let model = ProjectWindowModel(ref: .local(path: root.path), source: SampleDataSource(project: .studyHub), insightsDelay: .zero)
        XCTAssertEqual(model.projectRuns.plan.configurations.map(\.id), ["web-dev"])
        let sample = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))
        XCTAssertFalse(sample.projectRuns.canRun)
    }
}
