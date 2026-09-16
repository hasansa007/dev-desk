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

    /// Gemini publishes no sign-in verb — checked against its docs 2026-09-16, and absent, not undocumented.
    /// Its only documented path is running bare `gemini` and choosing from the menu, so that is what the row
    /// offers: an interactive open, no sign-out command, and no status to poll.
    func testGeminiSignsInByOpeningItselfBecauseItPublishesNoCommand() {
        let gemini = ToolDetection.auth(for: "gemini")
        XCTAssertEqual(gemini?.signIn, "gemini")
        XCTAssertNil(gemini?.signOut, "its sign-out is /auth logout inside its own session, not a shell command")
        XCTAssertNil(gemini?.status, "there is no status verb to ask")
        XCTAssertEqual(gemini?.interactive, true)
    }

    func testEveryOfferedCommandIsOneTheCliActuallyPublishes() {
        XCTAssertEqual(ToolDetection.auth(for: "codex")?.signIn, "codex login")
        XCTAssertEqual(ToolDetection.auth(for: "claude")?.signIn, "claude auth login")
        XCTAssertEqual(ToolDetection.auth(for: "opencode")?.signIn, "opencode auth login")
        XCTAssertNil(ToolDetection.auth(for: "nonesuch"))
    }

    /// `opencode auth list` draws a box and ends with a count, and colours it with ANSI escapes.
    /// This is its real output, pasted from the installed CLI rather than imagined.
    func testOpencodeIdentityIsReadFromItsCredentialCount() {
        let oneProvider = "\u{001B}[0m\n┌  Credentials \u{001B}[90m~/.local/share/opencode/auth.json\n│\n"
            + "●  OpenCode Zen \u{001B}[90mapi\n│\n└  1 credentials\n"
        XCTAssertEqual(AuthStatus.opencode(oneProvider), "provider · OpenCode Zen")

        let none = "┌  Credentials ~/.local/share/opencode/auth.json\n│\n└  0 credentials\n"
        XCTAssertNil(AuthStatus.opencode(none), "no credentials is signed out")

        let two = "┌  Credentials\n●  Anthropic api\n●  OpenCode Zen api\n└  2 credentials\n"
        XCTAssertEqual(AuthStatus.opencode(two), "2 providers · Anthropic…")

        XCTAssertNil(AuthStatus.opencode("command not found"), "an unreadable shape leaves no identity")
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
