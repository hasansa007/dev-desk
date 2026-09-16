import XCTest
@testable import DeskCore

/// Signing in is each CLI's own command, run in a terminal. What this guards is which row offers it, and what
/// each CLI's answer means — a row that offers a sign-in for a missing remote sends you to the wrong screen.
final class ConnectionAuthTests: XCTestCase {
    func testAFailureThatIsNotAboutAuthOffersNoSignIn() {
        let missingRepo = ToolDetection.github(.unavailable("Could not resolve to a Repository with the name 'acme/gone'."))
        XCTAssertNil(missingRepo.auth, "signing in again does not conjure a repository")
        XCTAssertFalse(missingRepo.isSignedOut)

        let signedOut = ToolDetection.github(.unavailable("gh auth: not logged in to github.com"))
        XCTAssertEqual(signedOut.auth?.signIn, "gh auth login")
        XCTAssertTrue(signedOut.isSignedOut)
    }

    func testEveryOfferedCommandIsOneTheCliActuallyPublishes() {
        XCTAssertEqual(ToolDetection.auth(for: "codex")?.signIn, "codex login")
        XCTAssertEqual(ToolDetection.auth(for: "claude")?.signIn, "claude auth login")
        // Not rows any more, so nothing to sign into from Accounts; they take hand-offs instead.
        XCTAssertNil(ToolDetection.auth(for: "gemini"))
        XCTAssertNil(ToolDetection.auth(for: "opencode"))
        XCTAssertNil(ToolDetection.auth(for: "nonesuch"))
    }

    /// `claude auth status` answers in JSON; a shape that changes must leave no identity rather than a wrong one.
    func testClaudeIdentityIsReadFromItsJSON() {
        let signedIn = #"{"loggedIn": true, "authMethod": "claude.ai", "email": "dev@example.com"}"#
        XCTAssertEqual(AuthStatus.claude(signedIn), "dev@example.com")
        XCTAssertEqual(AuthStatus.claude(#"{"loggedIn": true, "authMethod": "claude.ai"}"#), "signed in · claude.ai")
        XCTAssertNil(AuthStatus.claude(#"{"loggedIn": false}"#))
        XCTAssertNil(AuthStatus.claude("command not found"))
    }

    /// `codex login status` answers in one line.
    func testCodexIdentityIsReadFromItsLine() {
        XCTAssertEqual(AuthStatus.codex("Logged in using ChatGPT\n"), "signed in · ChatGPT")
        XCTAssertEqual(AuthStatus.codex("Logged in\n"), "signed in")
        XCTAssertNil(AuthStatus.codex("Not logged in\n"))
        XCTAssertNil(AuthStatus.codex(""))
    }
}
