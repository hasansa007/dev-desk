import XCTest
@testable import DeskCore

final class SessionAgentsTests: XCTestCase {
    func testTheDefaultListsClaudeAndCodex() {
        XCTAssertEqual(SessionAgents.builtIns(SessionAgents.defaultBuiltIns), [.claude, .codex])
    }

    /// The picker's order is the agents' own, not the order they happened to be ticked in.
    func testBuiltInsComeBackInAgentOrderAndUnknownNamesAreDropped() {
        XCTAssertEqual(SessionAgents.builtIns("opencode, claude,nope,,"), [.claude, .opencode])
        XCTAssertEqual(SessionAgents.store([.antigravity, .claude]), "claude,antigravity")
        XCTAssertEqual(SessionAgents.builtIns(""), [])
    }

    func testCustomAgentsRoundTripAndGarbageIsAnEmptyList() {
        let agents = [CustomSessionAgent(id: "a", name: "aider", command: "aider --model sonnet")]
        XCTAssertEqual(SessionAgents.decodeCustom(SessionAgents.encodeCustom(agents)), agents)
        XCTAssertEqual(SessionAgents.decodeCustom(Data("not json".utf8)), [])
    }

    /// A default that is no longer offered — unticked, removed — falls to the first choice, never to nothing.
    func testTheDefaultIsTheStoredChoiceWhileOfferedElseTheFirst() {
        let offered = ["claude", "custom:a", SessionAgents.terminalKey]
        XCTAssertEqual(SessionAgents.defaultChoice(stored: "custom:a", offered: offered), "custom:a")
        XCTAssertEqual(SessionAgents.defaultChoice(stored: "", offered: offered), "claude")
        XCTAssertEqual(SessionAgents.defaultChoice(stored: "codex", offered: offered), "claude")
        XCTAssertEqual(SessionAgents.defaultChoice(stored: "codex", offered: []), SessionAgents.terminalKey)
    }
}
