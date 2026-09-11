import Foundation
import XCTest
@testable import DeskCore

final class SafeFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("safefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsARegularFileWithinTheRoot() throws {
        let url = try write("report.md", "hello")
        XCTAssertEqual(SafeFile.read(url, maxBytes: 1_048_576, within: root), .text("hello"))
    }

    func testSkipsASymlink() throws {
        let secret = try write("secret.txt", "top secret")
        let link = root.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertEqual(SafeFile.read(link, maxBytes: 1_048_576, within: root), .skipped)
    }

    func testSkipsAFileReachedThroughASymlinkedParentOutsideTheRoot() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "secret".write(to: outside.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
        let linkedDir = root.appendingPathComponent("docs")
        try FileManager.default.createSymbolicLink(at: linkedDir, withDestinationURL: outside)
        XCTAssertEqual(SafeFile.read(linkedDir.appendingPathComponent("x.md"), maxBytes: 1_048_576, within: root), .skipped)
    }

    func testRefusesAFileOverTheCap() throws {
        let url = try write("big.md", String(repeating: "a", count: 2048))
        XCTAssertEqual(SafeFile.read(url, maxBytes: 1024, within: root), .tooLarge)
    }

    func testSkipsANonRegularFileLikeADirectory() {
        XCTAssertEqual(SafeFile.read(root, maxBytes: 1_048_576, within: root), .skipped)
    }

    func testSkipsAMissingFile() {
        XCTAssertEqual(SafeFile.read(root.appendingPathComponent("nope.md"), maxBytes: 1_048_576, within: root), .skipped)
    }
}
