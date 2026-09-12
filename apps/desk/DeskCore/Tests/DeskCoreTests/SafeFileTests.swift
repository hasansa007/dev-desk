import Foundation
import XCTest
@testable import DeskCore

final class SafeFileTests: XCTestCase {
    private var root: URL!
    private var cleanup: [URL] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("safefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A folder beside the root, on the same volume, standing in for the rest of the user's disk.
    private func outsideDirectory() throws -> URL {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        cleanup.append(outside)
        return outside
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

    func testRefusesAHardLinkToAFileOutsideTheRoot() throws {
        let secret = try outsideDirectory().appendingPathComponent("secret.md")
        try "top secret".write(to: secret, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("report.md")
        try FileManager.default.linkItem(at: secret, to: link)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: link.path)[.referenceCount] as? Int, 2)
        XCTAssertEqual(SafeFile.read(link, maxBytes: 1_048_576, within: root), .hardLink)
    }

    func testRefusesAFIFOWithoutBlocking() throws {
        let fifo = root.appendingPathComponent("report.md")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        let root = self.root!
        let result = Locked<SafeFile.Read?>(nil)
        let returned = expectation(description: "the read returns")
        DispatchQueue.global().async {
            result.set(SafeFile.read(fifo, maxBytes: 1_048_576, within: root))
            returned.fulfill()
        }
        wait(for: [returned], timeout: 5)
        // A reader stuck in open() is released by a writer, so a regression fails here instead of hanging the suite.
        let writer = open(fifo.path, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        XCTAssertEqual(result.get(), .skipped)
    }

    func testReadsThroughARootReachedByASymlink() throws {
        _ = try write("report.md", "hello")
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent("alias-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        cleanup.append(alias)
        XCTAssertEqual(SafeFile.read(alias.appendingPathComponent("report.md"), maxBytes: 1_048_576, within: alias), .text("hello"))
    }

    func testSwappingTheFileForASymlinkMidReadNeverYieldsTheTarget() throws {
        let secret = try outsideDirectory().appendingPathComponent("secret.md")
        try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        let report = try write("report.md", "original")
        let root = self.root!
        let stop = Locked(false)
        let swapper = DispatchGroup()
        DispatchQueue.global().async(group: swapper) {
            let link = root.appendingPathComponent("staged-link").path
            let file = root.appendingPathComponent("staged-file").path
            while !stop.get() {
                unlink(link)
                symlink(secret.path, link)
                rename(link, report.path)
                FileManager.default.createFile(atPath: file, contents: Data("original".utf8))
                rename(file, report.path)
            }
        }
        let results = (0..<2000).map { _ in SafeFile.read(report, maxBytes: 1024, within: root) }
        stop.set(true)
        swapper.wait()
        XCTAssertEqual(results.filter { $0 != .text("original") && $0 != .skipped }, [],
                       "a read either sees the file it opened or is refused, never the swapped-in symlink's target")
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
