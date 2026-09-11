import XCTest
@testable import DeskCore

final class SampleDataTests: XCTestCase {
    func testStudyHubColumnCounts() {
        let tasks = SampleData.studyHub().board.value ?? []
        func count(_ column: BoardColumn) -> Int { tasks.filter { $0.column == column }.count }
        XCTAssertEqual(count(.backlog), 2)
        XCTAssertEqual(count(.queued), 1)
        XCTAssertEqual(count(.inProgress), 3)
        XCTAssertEqual(count(.review), 1)
        XCTAssertEqual(count(.done), 1)
    }

    func testStudyHubSidebarBadges() {
        let snapshot = SampleData.studyHub()
        let tasks = snapshot.board.value ?? []
        let openTaskCount = tasks.filter { $0.column != .done }.count
        let findingsCount = snapshot.findings.value?.findings.count
        let pendingDecisionCount = (snapshot.decisions.value ?? []).filter { $0.state == .needsAttention }.count
        XCTAssertEqual(openTaskCount, 7)
        XCTAssertEqual(findingsCount, 3)
        XCTAssertEqual(pendingDecisionCount, 1)
    }

    func testTask42CarriesDesignContent() throws {
        let tasks = SampleData.studyHub().board.value ?? []
        let task = try XCTUnwrap(tasks.first { $0.id == "42" })
        XCTAssertEqual(task.activity.value?.count, 5)
        let requirements = try XCTUnwrap(task.requirements.value)
        XCTAssertEqual(requirements.criteria.count, 3)
        XCTAssertEqual(requirements.criteria.filter { $0.isMet }.count, 2)
        XCTAssertEqual(task.changes.value?.files.count, 3)
        XCTAssertEqual(task.evidence.value?.checks.count, 4)
        XCTAssertEqual(task.agents.count, 3)
        XCTAssertEqual(task.dock?.tabs.count, 3)
        XCTAssertEqual(task.dock?.splitTabID, "reviewer")
    }

    func testDevSkillBoardHasThreeTasks() {
        let tasks = SampleData.devSkill().board.value ?? []
        XCTAssertEqual(tasks.map(\.id), ["12", "9", "4"])
        XCTAssertEqual(tasks.map(\.column), [.inProgress, .review, .done])
    }

    private func deskLinkStrings(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "desk://[^\\s)]+") else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    func testEveryDeskLinkInSampleResolves() throws {
        let snapshot = SampleData.studyHub()
        let tasks = snapshot.board.value ?? []

        var texts: [String] = []
        for task in tasks {
            texts.append(contentsOf: (task.activity.value ?? []).map(\.text))
            texts.append(contentsOf: task.dependencies.map(\.text))
        }
        for theme in snapshot.roadmap.value?.themes ?? [] {
            texts.append(contentsOf: theme.items.compactMap(\.linkText))
        }
        texts.append(contentsOf: (snapshot.decisions.value ?? []).map(\.context))

        let taskIDs = Set(tasks.map(\.id))
        let findingIDs = Set(snapshot.findings.value?.findings.map(\.id) ?? [])
        let decisionIDs = Set(snapshot.decisions.value?.map(\.id) ?? [])

        var linkCount = 0
        for text in texts {
            for raw in deskLinkStrings(in: text) {
                let url = try XCTUnwrap(URL(string: raw))
                let link = try XCTUnwrap(DeskLink(url: url), "failed to parse \(raw)")
                linkCount += 1
                switch link {
                case .task(let id): XCTAssertTrue(taskIDs.contains(id), "unknown task id \(id)")
                case .finding(let id): XCTAssertTrue(findingIDs.contains(id), "unknown finding id \(id)")
                case .decision(let id): XCTAssertTrue(decisionIDs.contains(id), "unknown decision id \(id)")
                }
            }
        }
        XCTAssertGreaterThan(linkCount, 0)
    }

    func testDecisionTaskIDsExist() {
        let snapshot = SampleData.studyHub()
        let taskIDs = Set((snapshot.board.value ?? []).map(\.id))
        for decision in snapshot.decisions.value ?? [] {
            if let taskID = decision.taskID {
                XCTAssertTrue(taskIDs.contains(taskID), "decision \(decision.id) references missing task \(taskID)")
            }
        }
    }
}
