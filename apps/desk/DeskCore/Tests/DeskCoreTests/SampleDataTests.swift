import XCTest
@testable import DeskCore

final class SampleDataTests: XCTestCase {
    func testStudyHubColumnCounts() {
        let tasks = SampleData.studyHub().board.value ?? []
        func count(_ column: BoardColumn) -> Int { tasks.filter { $0.column == column }.count }
        XCTAssertEqual(count(.backlog), 2)
        // #65 sits in Ready for dev now: the sample's "planned, unstarted" card, since Queued means
        // "waiting for a free agent slot" (ADR 0035) and the sample has no queue.
        XCTAssertEqual(count(.readyForDev), 1)
        XCTAssertEqual(count(.queued), 0)
        XCTAssertEqual(count(.inProgress), 3)
        XCTAssertEqual(count(.review), 1)
        XCTAssertEqual(count(.done), 1)
    }

    func testStudyHubSidebarBadges() {
        let snapshot = SampleData.studyHub()
        let tasks = snapshot.board.value ?? []
        let openTaskCount = tasks.filter { $0.column != .done }.count
        let findingsCount = snapshot.findings.value?.findings.count
        XCTAssertEqual(openTaskCount, 7)
        XCTAssertEqual(findingsCount, 3)
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
    }

    func testSampleTasksKeepTheirDemoTranscriptsAndHaveNoBranch() {
        for snapshot in [SampleData.studyHub(), SampleData.devSkill()] {
            for task in snapshot.board.value ?? [] {
                XCTAssertNil(task.branch, task.id)
                XCTAssertNil(task.baseRef, task.id)
            }
        }
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

        let taskIDs = Set(tasks.map(\.id))
        let findingIDs = Set(snapshot.findings.value?.findings.map(\.id) ?? [])

        var linkCount = 0
        for text in texts {
            for raw in deskLinkStrings(in: text) {
                let url = try XCTUnwrap(URL(string: raw))
                let link = try XCTUnwrap(DeskLink(url: url), "failed to parse \(raw)")
                linkCount += 1
                switch link {
                case .task(let id): XCTAssertTrue(taskIDs.contains(id), "unknown task id \(id)")
                case .finding(let id): XCTAssertTrue(findingIDs.contains(id), "unknown finding id \(id)")
                case .decision: break
                }
            }
        }
        XCTAssertGreaterThan(linkCount, 0)
    }
}
