import Foundation
import XCTest
@testable import DeskCore

/// Answers from a set of installed launcher ids; anything else is reported absent.
struct FakeLauncherProbe: LauncherProbe {
    let installed: Set<String>

    func isInstalled(_ launcher: AcpLauncher) async -> Bool { installed.contains(launcher.id) }
}

final class AcpDetectionTests: XCTestCase {
    private let platform = "darwin-aarch64"

    private func registry() throws -> AcpRegistry { try AcpRegistryFixture.registry() }

    private func signedOutClaude() -> Connection {
        Connection(id: "claude", name: "Claude", state: .detected, label: "not signed in",
                   detail: "Claude is installed but not signed in; a run would stop at its own prompt.",
                   isSignedOut: true)
    }

    func testRunItHereHoldsOnlyTheAdaptersThatCanSpawnOnThisMachine() async throws {
        let runner = FakeRunner(["which npx": .ok("/opt/homebrew/bin/npx\n")])
        let choices = await AcpDetection.choices(registry: try registry(), connections: [], runner: runner,
                                                 probe: FakeLauncherProbe(installed: []), platform: platform)
        XCTAssertEqual(choices.here.map(\.id), ["claude-acp"])
        XCTAssertEqual(choices.here.first?.detail, "acp v1 · 0.78.0")
        XCTAssertNil(choices.hereEmptyReason)
    }

    /// The registry's `cmd` is relative to an archive we never download — `./dist-package/cursor-agent`.
    /// A tool its own installer put on PATH answers to the basename, and that is the same adapter.
    func testABinaryAdapterJoinsRunItHereOnceItsCommandResolves() async throws {
        let runner = FakeRunner(["which cursor-agent": .ok("/usr/local/bin/cursor-agent\n")])
        let choices = await AcpDetection.choices(registry: try registry(), connections: [], runner: runner,
                                                 probe: FakeLauncherProbe(installed: []), platform: platform)
        XCTAssertEqual(choices.here.map(\.id), ["cursor-agent"])
    }

    /// ADR 0036's rejected-fallback argument in code: no Node, but opencode installed, still means ACP.
    /// If this fails, "a machine without Node still has ACP" is false and amendment 1 costs more than claimed.
    func testAnInstalledBinaryAdapterCountsWithNoNpxOnThePath() async throws {
        let runner = FakeRunner(["which opencode": .ok("/opt/homebrew/bin/opencode\n")])
        let choices = await AcpDetection.choices(registry: try registry(), connections: [], runner: runner,
                                                 probe: FakeLauncherProbe(installed: []), platform: platform)
        XCTAssertEqual(choices.here.map(\.id), ["opencode"])
        XCTAssertNil(choices.hereEmptyReason, "an adapter was found, so there is nothing to explain")
    }

    func testRunItHereIsEmptyWithAReasonWhenNoAdapterCanSpawn() async throws {
        let runner = FakeRunner()
        let choices = await AcpDetection.choices(registry: try registry(), connections: [], runner: runner,
                                                 probe: FakeLauncherProbe(installed: ["terminal"]),
                                                 platform: platform)
        XCTAssertTrue(choices.here.isEmpty)
        XCTAssertEqual(choices.hereEmptyReason,
                       "No ACP adapter found: npx is not on PATH, and no agent ships a darwin-aarch64 binary this app can run.")
    }

    func testAnUnreadableRegistryIsItsOwnReasonRatherThanASilentEmptyList() async {
        let choices = await AcpDetection.choices(registry: nil, connections: [], runner: FakeRunner(),
                                                 probe: FakeLauncherProbe(installed: []), platform: platform)
        XCTAssertTrue(choices.here.isEmpty)
        XCTAssertEqual(choices.hereEmptyReason, "No ACP adapter found: the agent registry could not be read.")
    }

    func testASignedOutCliIsShownUnavailableInItsOwnWordsRatherThanDropped() async throws {
        let runner = FakeRunner(["which npx": .ok("/opt/homebrew/bin/npx\n")])
        let choices = await AcpDetection.choices(registry: try registry(), connections: [signedOutClaude()],
                                                 runner: runner, probe: FakeLauncherProbe(installed: []),
                                                 platform: platform)
        let row = try XCTUnwrap(choices.here.first { $0.id == "claude-acp" })
        XCTAssertFalse(row.isAvailable)
        XCTAssertEqual(row.detail, signedOutClaude().detail)
        XCTAssertNil(choices.hereEmptyReason)
    }

    func testNoHeadlessOrNonAcpRunnerCanEverAppearInRunItHere() async {
        let connections = [Connection(id: "claude", name: "Claude", state: .detected, label: "signed in"),
                           Connection(id: "codex", name: "Codex", state: .detected, label: "signed in")]
        let runner = FakeRunner(["which npx": .ok("/opt/homebrew/bin/npx\n"),
                                 "which claude": .ok("/usr/local/bin/claude\n"),
                                 "which codex": .ok("/usr/local/bin/codex\n")])
        let choices = await AcpDetection.choices(registry: nil, connections: connections, runner: runner,
                                                 probe: FakeLauncherProbe(installed: ["terminal"]),
                                                 platform: platform)
        XCTAssertTrue(choices.here.isEmpty)
        XCTAssertNotNil(choices.hereEmptyReason)
        XCTAssertTrue(choices.handoff.allSatisfy { $0.kind == .handoff })
        XCTAssertFalse(choices.handoff.contains { $0.id == "claude" || $0.id == "codex" })
    }

    func testTheListsAreOrderedByWhatCanBeChosenThenByName() async throws {
        let runner = FakeRunner(["which npx": .ok("/opt/homebrew/bin/npx\n"),
                                 "which cursor-agent": .ok("/usr/local/bin/cursor-agent\n")])
        let choices = await AcpDetection.choices(registry: try registry(), connections: [signedOutClaude()],
                                                 runner: runner,
                                                 probe: FakeLauncherProbe(installed: ["zed", "terminal"]),
                                                 platform: platform)
        // Cursor can be chosen, Claude is signed out, so Cursor leads whatever the registry's own order is.
        XCTAssertEqual(choices.here.map(\.id), ["cursor-agent", "claude-acp"])
        XCTAssertEqual(choices.handoff.map(\.id), ["terminal", "zed", "cursor", "iterm", "sc", "vscode"])
    }

    func testAnAbsentLauncherIsStillAHandoffRowSayingSo() async {
        let choices = await AcpDetection.choices(registry: nil, connections: [], runner: FakeRunner(),
                                                 probe: FakeLauncherProbe(installed: ["terminal"]),
                                                 platform: platform)
        XCTAssertEqual(choices.handoff.count, AcpDetection.launchers.count)
        let iterm = choices.handoff.first { $0.id == "iterm" }
        XCTAssertEqual(iterm?.isAvailable, false)
        XCTAssertEqual(iterm?.detail, "not installed")
        XCTAssertEqual(choices.runnable.map(\.id), ["terminal"])
    }

    func testTheDefaultProbeReadsBundleIdsWithSpotlightAndClisWithWhich() async {
        let runner = FakeRunner(["mdfind kMDItemCFBundleIdentifier == 'com.apple.Terminal'": .ok("/System/Applications/Utilities/Terminal.app\n"),
                                 "mdfind kMDItemCFBundleIdentifier == 'dev.zed.Zed'": .ok("\n"),
                                 "which sc": .ok("/usr/local/bin/sc\n")])
        let probe = CommandLauncherProbe(runner: runner)
        let installed = await AcpDetection.handoff(probe: probe).filter(\.isAvailable).map(\.id)
        XCTAssertEqual(installed, ["sc", "terminal"])
    }
}
