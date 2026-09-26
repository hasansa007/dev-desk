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
}
