import XCTest
@testable import DeskCore

final class AgentAvailabilityTests: XCTestCase {
    private func connection(_ id: String, _ name: String, state: ConnectionState = .detected,
                            signedOut: Bool = false, detail: String? = nil) -> Connection {
        Connection(id: id, name: name, state: state, label: signedOut ? "not signed in" : "connected",
                   detail: detail, isSignedOut: signedOut)
    }

    func testAnInstalledAndSignedInAgentIsReady() {
        let result = AgentAvailability.resolve(connectionName: "Claude",
                                               connections: [connection("claude", "Claude")])
        XCTAssertEqual(result, .ready(.claude))
    }

    /// The bug this type exists for: a signed-out CLI starts, prints its own login prompt and waits, so the
    /// Start button was enabled for a run that could never finish.
    func testAnInstalledButSignedOutAgentIsNotStartable() {
        let result = AgentAvailability.resolve(connectionName: "Claude",
                                               connections: [connection("claude", "Claude", signedOut: true)])
        guard case .unavailable(let reason) = result else { return XCTFail("a signed-out agent must not be ready") }
        XCTAssertTrue(reason.contains("signed in"), reason)
    }

    /// The CLI knows why better than we do — expired, rate-limited, logged out are not the same thing.
    func testASignedOutAgentIsRefusedInItsOwnWordsWhenItHasThem() {
        let detail = "Your Claude subscription has expired."
        let result = AgentAvailability.resolve(
            connectionName: "Claude",
            connections: [connection("claude", "Claude", signedOut: true, detail: detail)])
        XCTAssertEqual(result, .unavailable(reason: detail))
    }

    func testAnAgentThatIsNotInstalledIsNotStartable() {
        let result = AgentAvailability.resolve(connectionName: "Codex",
                                               connections: [connection("codex", "Codex", state: .missing)])
        guard case .unavailable(let reason) = result else { return XCTFail("a missing CLI must not be ready") }
        XCTAssertTrue(reason.contains("isn't installed"), reason)
    }

    func testAnAgentWithNoConnectionAtAllIsNotStartable() {
        guard case .unavailable = AgentAvailability.resolve(connectionName: "Codex", connections: []) else {
            return XCTFail("nothing detected means nothing to start")
        }
    }

    /// A Debug stand-in replaces the CLI, so it needs neither an install nor a sign-in.
    func testADebugStandInNeedsNeitherAnInstallNorASignIn() {
        let result = AgentAvailability.resolve(connectionName: "Claude",
                                               connections: [connection("claude", "Claude", state: .missing,
                                                                        signedOut: true)],
                                               hasStandIn: true)
        XCTAssertEqual(result, .ready(.claude))
    }
}
