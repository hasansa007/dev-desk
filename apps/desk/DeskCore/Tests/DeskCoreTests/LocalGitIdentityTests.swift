import XCTest
@testable import DeskCore

final class LocalGitIdentityTests: XCTestCase {
    func testIdentityReadsNameBranchAndHeadRevision() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("deskcore-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try runGit(["init", "-b", "main"], in: tempDir)
        try "hello".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: tempDir)
        try runGit(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial"], in: tempDir)

        let source = LocalGitDataSource(root: tempDir)
        let info = await source.identity()
        XCTAssertEqual(info.name, tempDir.lastPathComponent)
        XCTAssertEqual(info.branch, "main")
        XCTAssertNotNil(info.headRevision)
    }

    func testMissingFolderThrowsFolderMissing() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("deskcore-missing-\(UUID().uuidString)")
        let source = LocalGitDataSource(root: missing)
        do {
            _ = try await source.load()
            XCTFail("expected folderMissing")
        } catch let error as LocalProjectError {
            XCTAssertEqual(error, .folderMissing(missing.path))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }
}
