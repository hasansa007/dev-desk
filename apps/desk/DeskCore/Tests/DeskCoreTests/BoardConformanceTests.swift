import Foundation
import XCTest
@testable import DeskCore

/// `shared/board-rules.json` against `BoardBuilder` — the Swift half of ADR 0055's registry.
///
/// The Python half is `tests/state/test_board_conformance.py`. Both read the same file and both fail on a
/// rule they do not bind, so a rule added to one reader alone cannot go green. `desk.yml` lists the fixture
/// in its path filter for the same reason: a gate that does not run on the file it guards is not a gate.
final class BoardConformanceTests: XCTestCase {
    private typealias Case = [String: Any]

    /// The repository root from this file's own path, so the fixture is found wherever the package is checked out.
    private static let rules: [String: Any] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try! Data(contentsOf: root.appendingPathComponent("shared/board-rules.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    private func issue(_ c: Case) -> GitHubIssue {
        GitHubIssue(number: c["number"] as? Int ?? 1, title: c["title"] as? String ?? "",
                    labels: (c["labels"] as? [String] ?? []).map { GitHubLabel(name: $0) },
                    updatedAt: c["updatedAt"] as? String ?? "", body: c["body"] as? String ?? "")
    }

    /// Every rule in the registry needs a line here, which is what makes a missing one a failure.
    private func bindings() -> [String: (Case) -> AnyHashable] {
        [
            "branch_matches": { BoardBuilder.branch($0["name"] as! String, matches: $0["number"] as! Int) },
            "closed_issues": { BoardBuilder.closedIssues($0["body"] as! String).sorted() },
            "priority_rank": { BoardBuilder.priorityRank(self.issue($0)) },
            "slice_rank": { BoardBuilder.sliceRank(self.issue($0)) },
            "is_decomposed_epic": { BoardBuilder.isDecomposedEpic(self.issue($0)) },
            "order_next": { c in
                let issues = (c["issues"] as! [Case]).map(self.issue)
                return issues.sorted {
                    (BoardBuilder.priorityRank($0), BoardBuilder.sliceRank($0), $0.updatedAt, $0.number)
                        < (BoardBuilder.priorityRank($1), BoardBuilder.sliceRank($1), $1.updatedAt, $1.number)
                }.map(\.number)
            },
            "agent_prompt": {
                AgentLaunch.prompt(skillRoot: $0["skill_root"] as! String,
                                   taskNumber: $0["task_number"] as? Int, hasBranch: false)
            },
        ]
    }

    private static var registered: Set<String> { Set(rules.keys).subtracting(["_"]) }

    func testEveryRegisteredRuleIsBound() {
        XCTAssertEqual(Self.registered.subtracting(bindings().keys), [],
                       "shared/board-rules.json names a rule BoardBuilder does not implement")
        XCTAssertEqual(Set(bindings().keys).subtracting(Self.registered), [],
                       "a binding here has no rule in shared/board-rules.json")
    }

    func testEveryCaseMatches() {
        let bound = bindings()
        for name in Self.registered.sorted() {
            // An unbound rule is reported once by testEveryRegisteredRuleIsBound. Forcing it here instead
            // crashes the process, which fails the build while hiding every rule after it.
            guard let rule = bound[name] else { continue }
            let cases = (Self.rules[name] as! [String: Any])["cases"] as! [Case]
            for (i, item) in cases.enumerated() {
                let input = item["in"] as! Case
                XCTAssertEqual(rule(input), expectedValue(item["out"]!), "\(name) case \(i): \(input)")
            }
        }
    }

    /// JSON scalars arrive as NSNumber, which equals neither the Int nor the Bool a rule returns. The
    /// CFBoolean check is what keeps `true` from matching a case that says `1`.
    private func expectedValue(_ raw: Any) -> AnyHashable {
        if let numbers = raw as? [Int] { return numbers }
        if let text = raw as? String { return text }
        guard let number = raw as? NSNumber else { return raw as! AnyHashable }
        return CFGetTypeID(number) == CFBooleanGetTypeID() ? number.boolValue : number.intValue
    }
}
