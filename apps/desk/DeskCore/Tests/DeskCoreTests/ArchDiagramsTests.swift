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
        try write(root, "dev-family.architecture.json", "{\"meta\": {\"title\": \"The dev skill family\"}}")
        try write(root, "dev-journey.html", "<html></html>")
        // A sidecar of another kind names its diagram too; a file that is not a diagram is not one.
        try write(root, "dev-journey.workflow.json", "{\"meta\": {\"title\": \"A task's journey\"}}")
        try write(root, "notes.md", "not a diagram")

        let diagrams = ArchDiagrams.list(repositoryRoot: root.path)
        XCTAssertEqual(diagrams.map(\.id), ["dev-family", "dev-journey"])
        XCTAssertEqual(diagrams.map(\.title), ["The dev skill family", "A task's journey"])
        XCTAssertEqual(diagrams.first?.url.lastPathComponent, "dev-family.html")
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
}
