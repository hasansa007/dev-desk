import XCTest
@testable import DeskCore

final class FindingGroupsTests: XCTestCase {
    private func finding(_ id: String, _ categories: Set<FindingCategory>, _ locations: [String],
                         verification: String = "Code-inspected") -> Finding {
        Finding(id: id, runID: "r", title: id, listDetail: "", categories: categories, summary: "",
                verificationLabel: verification, locations: locations, limits: "")
    }

    func testStatusSectionsFollowTheOrderAndDropEmptyOnes() {
        let groups = FindingGroups.byStatus([
            finding("a", [.needsDecision], []),
            finding("b", [.new, .needsDecision], []),
            finding("c", [], []),
        ])
        XCTAssertEqual(groups.map(\.title), ["New", "Needs a decision", "Uncategorised"])
        XCTAssertEqual(groups[0].findings.map(\.id), ["b"])
    }

    func testFiledFindingsLeaveTheirCategoryForAFiledSection() {
        let groups = FindingGroups.byStatus([
            finding("a", [.new], []),
            finding("b", [.new], []),
            finding("c", [.needsDecision], []),
        ], filed: ["b", "c"])
        XCTAssertEqual(groups.map(\.title), ["New", "Filed"])
        XCTAssertEqual(groups[1].findings.map(\.id), ["b", "c"])
        XCTAssertNil(groups[1].category)
    }

    func testVerificationIsSharedOnlyWhenEveryRowSaysIt() {
        let same = FindingGroups.byStatus([finding("a", [.new], []), finding("b", [.new], [])])
        XCTAssertEqual(same[0].sharedVerification, "Code-inspected")
        let mixed = FindingGroups.byStatus([finding("a", [.new], []), finding("b", [.new], [], verification: "Unconfirmed")])
        XCTAssertNil(mixed[0].sharedVerification)
    }

    func testFileSectionsAreBusiestFirstAndCarryTheLines() {
        let groups = FindingGroups.byFile([
            finding("a", [.new], ["Store.swift:68"]),
            finding("b", [.new], ["List.swift:100", "Store.swift:103-105"]),
            finding("c", [.new], ["List.swift:101", "List.swift:107"]),
            finding("d", [.new], []),
        ])
        XCTAssertEqual(groups.map(\.title), ["Store.swift", "List.swift", "No source location"])
        XCTAssertEqual(groups[0].findings.map(\.id), ["a", "b"])
        XCTAssertEqual(groups[0].lines["b"], ":103-105")
        XCTAssertEqual(groups[1].lines["c"], ":101, :107")
    }

    func testABareNameAndAPathToTheSameFileAreOneSection() {
        let groups = FindingGroups.byFile([
            finding("a", [.new], ["App/Views/List.swift:100", "List.swift"]),
            finding("b", [.new], ["List.swift"]),
        ])
        XCTAssertEqual(groups.map(\.title), ["App/Views/List.swift"])
        XCTAssertEqual(groups[0].lines["a"], ":100")
        XCTAssertNil(groups[0].lines["b"])
    }

    func testALocationWithoutALineIsTheWholeFile() {
        XCTAssertEqual(FindingGroups.split("MockGenerator.swift").file, "MockGenerator.swift")
        XCTAssertNil(FindingGroups.split("MockGenerator.swift").line)
        XCTAssertEqual(FindingGroups.split("C:thing").file, "C:thing")
    }

    /// The source column names files; line ranges were all a head-truncated path had left to show.
    func testFileSummaryNamesFilesNotLines() {
        XCTAssertEqual(FindingGroups.fileSummary(["App/ContactDetailView.swift:104-115", "App/Store.swift:68"]),
                       "ContactDetailView.swift +1")
        XCTAssertEqual(FindingGroups.fileSummary(["A/List.swift:1", "List.swift:9-12"]), "List.swift")
        XCTAssertEqual(FindingGroups.fileSummary([]), "—")
    }
}
