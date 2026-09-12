import Foundation
import XCTest
@testable import DeskCore

final class FileTreeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("filetree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDirectoriesComeFirstThenFilesByName() throws {
        try write("beta.swift", "b")
        try write("Alpha.md", "a")
        _ = try makeDirectory("zebra")
        _ = try makeDirectory("Apples")
        XCTAssertEqual(FileTree.list(root, within: root).map(\.name), ["Apples", "zebra", "Alpha.md", "beta.swift"])
    }

    func testIgnoredAndHiddenEntriesAreListedBecauseTheBrowserHidesNothing() throws {
        try write(".env", "SECRET=1")
        _ = try makeDirectory("node_modules")
        XCTAssertEqual(FileTree.list(root, within: root).map(\.name), ["node_modules", ".env"])
    }

    func testASymlinkedDirectoryIsListedButNeverExpandable() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs"), withDestinationURL: outside)
        let entry = try XCTUnwrap(FileTree.list(root, within: root).first { $0.name == "docs" })
        XCTAssertTrue(entry.isSymlink)
        XCTAssertFalse(entry.isExpandable, "expanding it would leave the project")
    }

    func testADirectoryOutsideTheRootListsNothing() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "x".write(to: outside.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(FileTree.list(outside, within: root), [])
    }

    func testEntryIdsArePathsRelativeToTheProjectRoot() throws {
        let nested = try makeDirectory("Sources")
        try "x".write(to: nested.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        XCTAssertEqual(FileTree.list(nested, within: root).map(\.id), ["Sources/App.swift"])
    }

    func testTextFileIsReadAndASizeIsReported() throws {
        try write("README.md", "hello")
        XCTAssertEqual(FileReader.read(root.appendingPathComponent("README.md"), within: root), .text("hello"))
        XCTAssertEqual(FileTree.list(root, within: root).first?.size, 5)
    }

    func testAFileWithANulByteReadsAsBinary() throws {
        let url = root.appendingPathComponent("logo.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]).write(to: url)
        XCTAssertEqual(FileReader.read(url, within: root), .binary)
    }

    func testAFileOverTheCapIsNotRead() throws {
        try write("big.txt", String(repeating: "a", count: 4096))
        XCTAssertEqual(FileReader.read(root.appendingPathComponent("big.txt"), maxBytes: 1024, within: root), .tooLarge(1024))
    }

    func testASymlinkIsNotFollowedAndSaysSo() throws {
        let secret = try write("secret.txt", "top secret")
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        guard case .unreadable(let reason) = FileReader.read(link, within: root) else {
            return XCTFail("a symlink must not be followed")
        }
        XCTAssertTrue(reason.contains("symbolic link"))
    }

    func testEveryPreviewThatCannotRenderSaysWhy() {
        XCTAssertNotNil(FilePreview.binary.message)
        XCTAssertNotNil(FilePreview.tooLarge(262_144).message)
        XCTAssertNotNil(FilePreview.unreadable("x").message)
        XCTAssertNil(FilePreview.text("x").message)
    }
}
