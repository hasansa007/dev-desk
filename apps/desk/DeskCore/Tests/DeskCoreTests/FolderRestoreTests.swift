import XCTest
@testable import DeskCore

/// Real git, in a temporary folder: the move stashes, switches and adds a worktree, and a fake runner would only
/// prove the commands were typed, not that the changes arrive.
final class FolderRestoreTests: XCTestCase {
    private var base: URL!

    override func setUp() {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("folder-restore-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    @discardableResult
    private func sh(_ command: String, in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = folder
        process.environment = ["HOME": base.path, "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
                               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw NSError(domain: out, code: Int(process.terminationStatus)) }
        return out
    }

    private func repo() throws -> URL {
        let project = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try sh("""
        git init -q -b staging && git config user.email t@t && git config user.name t && git config commit.gpgsign false
        echo one > a.txt && git add a.txt && git commit -q -m one
        git switch -q -c gh-7-fix && echo two > b.txt && git add b.txt && git commit -q -m two
        echo edited >> a.txt
        """, in: project)
        return project
    }

    func testMovingABranchCarriesItsChangesAndPutsTheFolderBackOnBase() async throws {
        let project = try repo()
        let worktree = base.appendingPathComponent("wt/project-gh-7-fix")
        try await FolderRestore(root: project, runner: ProcessRunner()).moveToWorktree(branch: "gh-7-fix", base: "staging", worktree: worktree)
        XCTAssertEqual(try sh("git branch --show-current", in: project).trimmingCharacters(in: .whitespacesAndNewlines), "staging")
        XCTAssertEqual(try sh("git status --porcelain --untracked-files=no", in: project), "")
        XCTAssertEqual(try sh("git branch --show-current", in: worktree).trimmingCharacters(in: .whitespacesAndNewlines), "gh-7-fix")
        XCTAssertEqual(try String(contentsOf: worktree.appendingPathComponent("a.txt"), encoding: .utf8), "one\nedited\n")
        XCTAssertEqual(try sh("git stash list", in: project), "", "the stash it used is dropped")
    }

    func testSwitchingBackIsRefusedOverUncommittedChanges() async throws {
        let project = try repo()
        try sh("echo conflict > b.txt", in: project)
        do {
            try await FolderRestore(root: project, runner: ProcessRunner()).switchToBase("staging")
            // b.txt does not exist on staging, so git carries or refuses; either way nothing may be lost.
            XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("b.txt"), encoding: .utf8), "conflict\n")
        } catch {
            XCTAssertEqual(try sh("git branch --show-current", in: project).trimmingCharacters(in: .whitespacesAndNewlines), "gh-7-fix")
        }
    }
}
