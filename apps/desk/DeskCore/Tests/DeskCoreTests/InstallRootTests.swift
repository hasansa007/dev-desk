import XCTest
@testable import DeskCore

final class InstallRootTests: XCTestCase {
    private let home = "/Users/me"

    func testThePreferredRootWinsWhenBothAreInstalled() {
        XCTAssertEqual(InstallRoot.resolve(InstallRoot.claude, home: home, exists: { _ in true }), InstallRoot.claude)
    }

    func testTheFallbackAnswersForAMachineInstalledBefore0054() {
        XCTAssertEqual(InstallRoot.resolve(InstallRoot.claude, home: home,
                                           exists: { $0 == "/Users/me/.claude/skills/dev" }),
                       ".claude/skills/dev")
    }

    /// `skill_root` returns the named root when nothing is installed, so a prompt names the path the family
    /// belongs at. A reader can act on that; an empty string or a stale link cannot be told from a real one.
    func testNeitherInstalledReturnsTheDeclaredRoot() {
        XCTAssertEqual(InstallRoot.resolve(InstallRoot.claude, home: home, exists: { _ in false }), InstallRoot.claude)
    }

    /// ADR 0054 moved Claude Code's root alone. Codex's copy never moved, so it has no fallback to find.
    func testCodexHasNoFallback() {
        XCTAssertEqual(InstallRoot.resolve(InstallRoot.codex, home: home, exists: { _ in false }), InstallRoot.codex)
        XCTAssertNil(InstallRoot.fallbacks[InstallRoot.codex])
    }
}
