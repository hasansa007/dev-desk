import XCTest
@testable import DeskCore

final class ArchDiagramsTests: XCTestCase {
    private func makeFolder() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(ArchDiagrams.folder), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ root: URL, _ name: String, _ contents: String) throws {
        try contents.write(to: root.appendingPathComponent(ArchDiagrams.folder).appendingPathComponent(name),
                           atomically: true, encoding: .utf8)
    }

    func testDiagramsAreListedWithTheirSidecarTitles() throws {
        let root = try makeFolder()
        try write(root, "dev-family.html", "<html></html>")
        try write(root, "dev-family.architecture.json", "{\"diagram_type\": \"architecture\", \"meta\": {\"title\": \"The dev skill family\"}}")
        try write(root, "dev-journey.html", "<html></html>")
        // A sidecar of another kind names its diagram too; a file that is not a diagram is not one.
        try write(root, "dev-journey.workflow.json", "{\"diagram_type\": \"workflow\", \"meta\": {\"title\": \"A task's journey\"}}")
        try write(root, "notes.md", "not a diagram")

        let diagrams = ArchDiagrams.list(repositoryRoot: root.path)
        XCTAssertEqual(diagrams.map(\.id), ["dev-family", "dev-journey"])
        XCTAssertEqual(diagrams.map(\.title), ["The dev skill family", "A task's journey"])
        XCTAssertEqual(diagrams.first?.url.lastPathComponent, "dev-family.html")
    }

    /// The type a diagram was drawn as comes from the sidecar's `diagram_type`, so Regenerate can redraw it as itself.
    func testDiagramCarriesItsKindFromTheSidecar() throws {
        let root = try makeFolder()
        try write(root, "dev-family.html", "<html></html>")
        try write(root, "dev-family.architecture.json", "{\"diagram_type\": \"architecture\", \"meta\": {\"title\": \"X\"}}")
        try write(root, "flows.html", "<html></html>")
        try write(root, "flows.dataflow.json", "{\"diagram_type\": \"dataflow\", \"meta\": {\"title\": \"Y\"}}")

        let byID = Dictionary(uniqueKeysWithValues: ArchDiagrams.list(repositoryRoot: root.path).map { ($0.id, $0.kind) })
        XCTAssertEqual(byID["dev-family"], "architecture")
        XCTAssertEqual(byID["flows"], "dataflow")
    }

    /// A sidecar that names no type leaves kind nil; the screen falls back to a whole-project architecture run.
    func testADiagramWithoutADiagramTypeHasNoKind() throws {
        let root = try makeFolder()
        try write(root, "dev-system.html", "<html></html>")
        try write(root, "dev-system.architecture.json", "{\"meta\": {\"title\": \"Dev system\"}}")
        XCTAssertNil(ArchDiagrams.list(repositoryRoot: root.path).first?.kind)
    }

    func testAnUntitledDiagramFallsBackToItsFileName() throws {
        let root = try makeFolder()
        try write(root, "dev-system.html", "<html></html>")
        try write(root, "dev-system.architecture.json", "{\"meta\": {}}")
        XCTAssertEqual(ArchDiagrams.list(repositoryRoot: root.path).map(\.title), ["Dev system"])
    }

    /// A repository that has never run dev:arch is the ordinary case, not a failure.
    func testAMissingFolderListsNothing() {
        XCTAssertTrue(ArchDiagrams.list(repositoryRoot: "/nope/not/here").isEmpty)
    }

    /// The five kinds the Diagrams screen always lists, in the skill's own order.
    func testTheFiveKindsAreTheDevArchTypesInOrder() {
        XCTAssertEqual(ArchDiagrams.kinds, ["architecture", "workflow", "dataflow", "sequence", "lifecycle"])
    }

    /// A kind's item shows the newest file of that kind: a repo that drew the same kind twice keeps both, and
    /// the most recently written one wins.
    func testNewestOfAKindWinsWhenDrawnMoreThanOnce() throws {
        let root = try makeFolder()
        try write(root, "old.html", "<html></html>")
        try write(root, "old.dataflow.json", "{\"diagram_type\": \"dataflow\", \"meta\": {\"title\": \"Old flow\"}}")
        try write(root, "new.html", "<html></html>")
        try write(root, "new.dataflow.json", "{\"diagram_type\": \"dataflow\", \"meta\": {\"title\": \"New flow\"}}")
        // Make "new" the more recently modified HTML, whatever order the filesystem enumerates them in.
        let dir = root.appendingPathComponent(ArchDiagrams.folder)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: dir.appendingPathComponent("old.html").path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                              ofItemAtPath: dir.appendingPathComponent("new.html").path)

        let newest = ArchDiagrams.newest(kind: "dataflow", repositoryRoot: root.path)
        XCTAssertEqual(newest?.title, "New flow")
    }

    /// A kind nothing has drawn has no diagram — that is the "Generate" state, not an error.
    func testAKindWithNoFileHasNoNewest() throws {
        let root = try makeFolder()
        try write(root, "a.html", "<html></html>")
        try write(root, "a.architecture.json", "{\"diagram_type\": \"architecture\", \"meta\": {\"title\": \"A\"}}")
        XCTAssertNil(ArchDiagrams.newest(kind: "lifecycle", repositoryRoot: root.path))
        XCTAssertNotNil(ArchDiagrams.newest(kind: "architecture", repositoryRoot: root.path))
    }
}
