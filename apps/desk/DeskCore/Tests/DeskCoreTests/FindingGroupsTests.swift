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
        XCTAssertEqual(groups.map(\.title), ["Needs your decision", "Not verified yet", "Uncategorised"])
        XCTAssertEqual(groups[0].findings.map(\.id), ["b"])
    }

    func testFiledFindingsLeaveTheirCategoryForAFiledSection() {
        let groups = FindingGroups.byStatus([
            finding("a", [.new], []),
            finding("b", [.new], []),
            finding("c", [.needsDecision], []),
        ], filed: ["b", "c"])
        XCTAssertEqual(groups.map(\.title), ["Needs your decision", "Filed"])
        XCTAssertEqual(groups[1].findings.map(\.id), ["b", "c"])
        XCTAssertNil(groups[1].category)
    }

    func testAMergedFindingIsNotCountedAsFiled() {
        var merged = finding("m", [.new], [])
        merged.filing = .merged(782)
        var filedOne = finding("f", [.new], [])
        filedOne.filing = .filed(810)
        let groups = FindingGroups.byStatus([finding("a", [.new], []), filedOne, merged], filed: ["f", "m"])
        XCTAssertEqual(groups.map(\.title), ["Needs your decision", "Filed", "Added to an open issue"])
        XCTAssertEqual(groups[1].findings.map(\.id), ["f"])
        XCTAssertEqual(groups[2].findings.map(\.id), ["m"])
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

    /// A row labels each file once; line ranges were all a head-truncated path had left to show.
    func testFileNamesAreOneLabelPerFile() {
        let locations = ["App/ContactDetailView.swift:104-115", "App/Store.swift:68", "ContactDetailView.swift:9"]
        XCTAssertEqual(FindingGroups.fileNames(locations), ["ContactDetailView.swift", "Store.swift"])
        XCTAssertEqual(FindingGroups.locations(locations, inFile: "ContactDetailView.swift"),
                       ["App/ContactDetailView.swift:104-115", "ContactDetailView.swift:9"])
        XCTAssertEqual(FindingGroups.fileNames([]), [])
        XCTAssertEqual(FindingGroups.fileNames(["Tests.swift", "and whatever each testable seam needs", "and"]), ["Tests.swift"])
    }

    // MARK: - Grouped reports (ADR 0040)

    private let groupedReport = """
    # Findings — Demo — 2026-09-16

    ## GROUPS (1)
    ### G1 · Contact access and loading
    branch: group/contact-access · why: needs chain — each builds on the state the one before leaves
    1. C1 — Load contacts off the main thread
    2. C2 — "Don't Allow" shows the error screen

    ## CONFIRMED (3)
    1. **Load contacts off the main thread** · `ContactsStore.swift:68` · mechanism: runs on the main actor
       id: C1   type: Data flow   group: G1 · 1 of 2
       touches: ContactsStore.swift › load(); ContactsListView.swift › content
       cases: #2 fetch on main · arch-4 comment claims the fix
    2. **"Don't Allow" shows the error screen** · `ContactsStore.swift:103` · mechanism: requestAccess throws on denial
       id: C2   type: Logic   group: G1 · 2 of 2
       touches: ContactsStore.swift › requestAccessIfNeeded(), load()
       needs: C1 — both edit load()
       shares: C3 ContactsStore.swift › init(contacts:state:) — different code, parallel
       held: P1 limited access with zero contacts — low: no documented way to reach it
    3. **Birthdays show the wrong date** · `Contact.swift:73` · mechanism: date(from:) fills year 1
       id: C3   type: Logic   group: none
       touches: Contact.swift › init(_:)

    ## PLAUSIBLE (1)
    - **Limited access with zero contacts shows an empty list** · no documentation found
      id: P1   near: C2
    """

    func testAGroupedReportReadsIdsTypesAndLinks() {
        let findings = FindingsReportParser.parse(groupedReport, runID: "r")
        XCTAssertEqual(findings.map(\.id), ["r-C1", "r-C2", "r-C3", "r-P1"])
        let second = findings[1].coordination
        XCTAssertEqual(second.type, .logic)
        XCTAssertEqual(second.groupRef, "G1")
        XCTAssertEqual(second.position, "2 of 2")
        XCTAssertEqual(second.touches, [CodeTouch(file: "ContactsStore.swift", code: "requestAccessIfNeeded(), load()")])
        XCTAssertEqual(second.needs, [TicketLink(ref: "C1", note: "both edit load()", waits: true)])
        XCTAssertEqual(second.shares.first?.ref, "C3")
        XCTAssertEqual(second.shares.first?.waits, false)
        XCTAssertEqual(second.waitsFor, ["C1"])
        XCTAssertEqual(second.held.count, 1)
        XCTAssertEqual(findings[0].coordination.cases.count, 2)
        XCTAssertNil(findings[2].coordination.groupRef)
        // Field lines are coordination, not prose.
        XCTAssertFalse(findings[1].summary.contains("needs"))
        XCTAssertTrue(findings[0].locations.contains("ContactsListView.swift"))
    }

    func testByGroupRunsGroupsInOrderThenOwnThenHeld() {
        let findings = FindingsReportParser.parse(groupedReport, runID: "r")
        let groups = FindingsReportParser.groups(groupedReport, runID: "r")
        XCTAssertEqual(groups.first?.branch, "group/contact-access")
        XCTAssertEqual(groups.first?.members, ["C1", "C2"])
        let sections = FindingGroups.byGroup(findings, groups: groups)
        XCTAssertEqual(sections.map(\.title), ["Contact access and loading", "On its own", "Held"])
        XCTAssertEqual(sections[0].findings.map(\.id), ["r-C1", "r-C2"])
        XCTAssertEqual(sections[1].findings.map(\.id), ["r-C3"])
    }

    func testAReportWithoutGroupsFallsBackToStatus() {
        let findings = FindingsReportParser.parse(groupedReport, runID: "r")
        XCTAssertEqual(FindingGroups.byGroup(findings, groups: []).map(\.id), FindingGroups.byStatus(findings).map(\.id))
    }
}
