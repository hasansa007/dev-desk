import XCTest
@testable import DeskCore

final class StartRunnersTests: XCTestCase {
    private func connection(_ id: String, signedOut: Bool = false,
                            state: ConnectionState = .detected) -> Connection {
        Connection(id: id, name: id.capitalized, state: state,
                   label: signedOut ? "not signed in" : "signed in", isSignedOut: signedOut)
    }

    func testAnInstalledSignedInAgentCanCarryTheLaunch() {
        let choices = StartRunners.choices(connections: [connection("claude"), connection("codex")])
        XCTAssertEqual(choices.here.filter(\.isAvailable).map(\.id), ["claude", "codex"])
        XCTAssertNil(choices.hereEmptyReason)
        XCTAssertEqual(choices.here.first?.detail, "terminal",
                       "it runs in a session this app hosts — calling it acp would name a substrate that is not built")
    }

    /// Gemini, opencode and Antigravity run in the same built-in terminal, after Claude and Codex. They cannot be
    /// queued, so a full limit shows them unavailable instead of starting past it.
    func testOtherCLIsJoinRunItHereAndWaitForAFreeSlot() {
        let open = StartRunners.choices(connections: [connection("claude"), connection("codex")],
                                        terminalAgents: [.gemini, .opencode, .antigravity])
        XCTAssertEqual(open.here.map(\.id), ["claude", "codex", "gemini", "opencode", "antigravity"])
        XCTAssertEqual(open.here.map(\.detail), ["terminal", "terminal", "terminal", "terminal", "terminal"])
        XCTAssertTrue(open.here.allSatisfy(\.isAvailable))

        let full = StartRunners.choices(connections: [connection("claude")], terminalAgents: [.gemini], hasFreeSlot: false)
        XCTAssertEqual(full.here.first { $0.id == "gemini" }?.detail, "no free slot")
        XCTAssertEqual(full.here.first { $0.id == "gemini" }?.isAvailable, false)
    }

    /// A row that cannot be chosen is shown with the reason rather than dropped: absence is information,
    /// and a list that silently omits Claude looks like Claude does not exist.
    func testAnUnusableAgentIsShownWithItsReasonRatherThanHidden() {
        let choices = StartRunners.choices(connections: [connection("claude", signedOut: true),
                                                         connection("codex", state: .missing)])
        XCTAssertEqual(choices.here.count, 2)
        XCTAssertTrue(choices.here.allSatisfy { !$0.isAvailable })
        XCTAssertEqual(choices.here.first { $0.id == "claude" }?.detail, "not signed in")
        XCTAssertEqual(choices.here.first { $0.id == "codex" }?.detail, "not installed")
    }

    /// The empty state names WHICH problem it is, because signing in and installing are different fixes.
    func testNothingRunnableSaysWhichProblemItIs() {
        let signedOut = StartRunners.choices(connections: [connection("claude", signedOut: true),
                                                           connection("codex", state: .missing)])
        XCTAssertEqual(signedOut.hereEmptyReason?.contains("not signed in"), true)
        XCTAssertEqual(signedOut.hereEmptyReason?.contains("Settings → Accounts"), true)

        let nothingInstalled = StartRunners.choices(connections: [connection("claude", state: .missing),
                                                                  connection("codex", state: .missing)])
        XCTAssertEqual(nothingInstalled.hereEmptyReason?.contains("No agent CLI is installed"), true)
    }

    func testTheSheetNeverOffersARunTheStartWouldThenRefuse() {
        // One source of truth: every runnable row must also satisfy the gate that dispatches it.
        let connections = [connection("claude"), connection("codex", signedOut: true)]
        for row in StartRunners.choices(connections: connections).here where row.isAvailable {
            let kind = AgentKind(rawValue: row.id)
            let name = kind.map(AgentLaunch.connectionName) ?? row.id
            guard case .ready = AgentAvailability.resolve(connectionName: name, connections: connections) else {
                return XCTFail("\(row.id) is offered but AgentAvailability refuses it")
            }
        }
    }

    func testHandoffRowsAreCarriedThroughUntouched() {
        let terminal = RunnerOption(id: "terminal", name: "Terminal", detail: "--from-file", kind: .handoff)
        let choices = StartRunners.choices(connections: [connection("claude")], handoff: [terminal])
        XCTAssertEqual(choices.handoff, [terminal])
        XCTAssertFalse(choices.here.contains { $0.kind == .handoff })
    }
}
