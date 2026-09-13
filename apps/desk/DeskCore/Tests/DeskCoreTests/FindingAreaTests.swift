import XCTest
@testable import DeskCore

final class FindingAreaTests: XCTestCase {
    func testAPathNamesItsArea() {
        XCTAssertEqual(FindingArea.of(path: "Screens/MainScreen.swift:42"), .ui)
        XCTAssertEqual(FindingArea.of(path: "src/components/Header.tsx"), .ui)
        XCTAssertEqual(FindingArea.of(path: "Services/ReminderService.swift:42-52"), .logic)
        XCTAssertEqual(FindingArea.of(path: "Tests/DefaultReminderServiceTests.swift:98"), .tests)
        XCTAssertEqual(FindingArea.of(path: "Stubs/ReminderDataSourceStub.swift:34"), .tests)
        XCTAssertEqual(FindingArea.of(path: ".github/workflows/ci.yml"), .ci)
        XCTAssertEqual(FindingArea.of(path: "docs/adr/0026-one-session.md"), .docs)
        XCTAssertEqual(FindingArea.of(path: "apps/desk/project.yml"), .config)
        XCTAssertEqual(FindingArea.of(path: "app/db/migrations/003_add_index.sql"), .data)
    }

    /// A workflow that lints Swift is still CI, and a test that renders a view is still a test.
    func testTheMoreSpecificRuleWins() {
        XCTAssertEqual(FindingArea.of(path: ".github/workflows/swiftlint.yml"), .ci)
        XCTAssertEqual(FindingArea.of(path: "Tests/UI/LoginScreenTests.swift"), .tests)
    }

    func testTheCommonestAreaWins() {
        XCTAssertEqual(FindingArea.of(paths: ["MainScreen.swift:57", "ProjectsScreen.swift:14",
                                              "AnalyticsScreen.swift:13", "MainCoordinator.swift"]), .ui)
        XCTAssertEqual(FindingArea.of(paths: ["Services/ReminderService.swift:42",
                                              "Services/ReminderService.swift"]), .logic)
    }

    /// Nothing to read means no area, not a guess.
    func testNoLocationsMeansNoArea() {
        XCTAssertNil(FindingArea.of(paths: []))
        XCTAssertNil(FindingArea.of(path: "somewhere"))
    }

    func testAFindingCarriesItsArea() {
        let report = "## CONFIRMED (1)\n- Tab state bleeds · `MainScreen.swift:57` · `ProjectsScreen.swift:14`\n"
        XCTAssertEqual(SurveyReportParser.parse(report, runID: "r")[0].area, .ui)
    }
}
