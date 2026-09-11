import Foundation
import XCTest
@testable import DeskCore

final class ProjectOperationsTests: XCTestCase {
    private let projectMap = "# PROJECT_MAP\n\n## TECH_STACK\n\n## SYSTEM_FLOW\n\n## ORPHANS & PENDING\n"

    func testCreateMakesAGitRepositoryWithAProjectMap() async throws {
        let parent = try TempGitRepo()
        let folder = try await ProjectOperations.createProject(named: "  New App  ", in: parent.url)
        XCTAssertEqual(folder.path, parent.url.appendingPathComponent("New App").path)
        XCTAssertFalse(folder.absoluteString.hasSuffix("/"), "a trailing slash would not match a picked folder's path")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("PROJECT_MAP.md"), encoding: .utf8), projectMap)
    }

    func testCreateRefusesNamesThatAreNotASingleFolder() async throws {
        let parent = try TempGitRepo()
        for name in ["a/b", "a:b", ".", "..", "", "   "] {
            do {
                _ = try await ProjectOperations.createProject(named: name, in: parent.url, runner: FakeRunner())
                XCTFail("expected \(name.debugDescription) to be refused")
            } catch let error as ProjectOperationError {
                XCTAssertEqual(error, .invalidName(name.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.url.path), [])
    }

    func testCreateRefusesAnExistingFolder() async throws {
        let parent = try TempGitRepo()
        try parent.write("Taken/keep.txt", "mine")
        let runner = FakeRunner()
        do {
            _ = try await ProjectOperations.createProject(named: "Taken", in: parent.url, runner: runner)
            XCTFail("expected destinationExists")
        } catch let error as ProjectOperationError {
            XCTAssertEqual(error, .destinationExists(parent.url.appendingPathComponent("Taken").path))
        }
        XCTAssertEqual(runner.calls, [])
        XCTAssertEqual(try String(contentsOf: parent.url.appendingPathComponent("Taken/keep.txt"), encoding: .utf8), "mine")
    }

    func testFailedInitReportsStderrAndRemovesTheNewFolder() async throws {
        let parent = try TempGitRepo()
        let runner = FakeRunner(["git init": .failed(1, stderr: "hint: something\nfatal: cannot write config\n")])
        do {
            _ = try await ProjectOperations.createProject(named: "Broken", in: parent.url, runner: runner)
            XCTFail("expected initFailed")
        } catch let error as ProjectOperationError {
            XCTAssertEqual(error, .initFailed("hint: something\nfatal: cannot write config"))
        }
        XCTAssertEqual(runner.calls.first?.directory?.path, parent.url.appendingPathComponent("Broken").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.url.appendingPathComponent("Broken").path))
    }

    func testCloneFromALocalRepositoryPathSucceeds() async throws {
        let source = try TempGitRepo()
        try source.git("init", "-q", "-b", "main")
        try source.write("README.md", "hello\n")
        try source.commitAll("initial")
        let parent = try TempGitRepo()

        let folder = try await ProjectOperations.cloneRepository(url: " \(source.url.path)/ ", into: parent.url)
        XCTAssertEqual(folder.path, parent.url.appendingPathComponent(source.url.lastPathComponent).path)
        XCTAssertFalse(folder.absoluteString.hasSuffix("/"), "a trailing slash would not match a picked folder's path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8), "hello\n")
    }

    func testCloneRefusesRemoteHelperTransportsWithoutRunningGit() async throws {
        let parent = try TempGitRepo()
        let runner = FakeRunner()
        for url in ["ext::sh -c \"touch /tmp/pwned\"", "  fd::17/foo ", "EXT::sh -c whoami"] {
            do {
                _ = try await ProjectOperations.cloneRepository(url: url, into: parent.url, runner: runner)
                XCTFail("expected unsupportedURL for \(url.debugDescription)")
            } catch let error as ProjectOperationError {
                XCTAssertEqual(error, .unsupportedURL(url.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        XCTAssertEqual(runner.calls, [])
    }

    func testOrdinaryURLsAreNotMistakenForTransports() {
        XCTAssertNil(ProjectOperations.transport(of: "https://github.com/acme/app.git"))
        XCTAssertNil(ProjectOperations.transport(of: "git@github.com:acme/app.git"))
        XCTAssertNil(ProjectOperations.transport(of: "/tmp/code/repo"))
        XCTAssertEqual(ProjectOperations.transport(of: "ext::sh -c x"), "ext")
        XCTAssertEqual(ProjectOperations.transport(of: "FD::17"), "fd")
    }

    func testCloneUsesTheProtocolWhitelistButStillAllowsLocalPaths() async throws {
        XCTAssertEqual(ProjectOperations.cloneEnvironment["GIT_ALLOW_PROTOCOL"], "https:ssh:git:file")
        let source = try TempGitRepo()
        try source.git("init", "-q", "-b", "main")
        try source.write("README.md", "hi\n")
        try source.commitAll("initial")
        let parent = try TempGitRepo()
        let folder = try await ProjectOperations.cloneRepository(url: source.url.path, into: parent.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path))
    }

    func testCloneRefusesAnExistingDestinationWithoutRunningGit() async throws {
        let parent = try TempGitRepo()
        try parent.write("app/keep.txt", "mine")
        let runner = FakeRunner()
        do {
            _ = try await ProjectOperations.cloneRepository(url: "https://github.com/acme/app.git", into: parent.url, runner: runner)
            XCTFail("expected destinationExists")
        } catch let error as ProjectOperationError {
            XCTAssertEqual(error, .destinationExists(parent.url.appendingPathComponent("app").path))
        }
        XCTAssertEqual(runner.calls, [])
    }

    func testCloneRunsGitWithSeparatorInTheParentAndReportsItsLastErrorLine() async throws {
        let parent = try TempGitRepo()
        let destination = parent.url.appendingPathComponent("app").path
        let key = "git clone -- https://github.com/acme/app.git \(destination)"
        let runner = FakeRunner([key: .failed(128, stderr: "Cloning into 'app'...\nfatal: repository 'https://github.com/acme/app.git/' not found\n\n")])
        do {
            _ = try await ProjectOperations.cloneRepository(url: "https://github.com/acme/app.git", into: parent.url, runner: runner)
            XCTFail("expected cloneFailed")
        } catch let error as ProjectOperationError {
            XCTAssertEqual(error, .cloneFailed("fatal: repository 'https://github.com/acme/app.git/' not found"))
        }
        XCTAssertEqual(runner.calls, [FakeRunner.Call(key: key, directory: parent.url, timeout: CommandTimeout.clone)])
    }

    func testCloneFolderNameComesFromTheURL() {
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: "https://github.com/acme/app.git/"), "app")
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: "git@github.com:acme/studyhub.git"), "studyhub")
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: "git@example.com:repo.git"), "repo")
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: "/tmp/code/repo"), "repo")
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: "https://github.com/acme/.."), "..")
        XCTAssertEqual(ProjectOperations.folderName(fromCloneURL: ""), "")
    }

    func testCloneRefusesAURLWithNoUsableFolderName() async throws {
        let parent = try TempGitRepo()
        let runner = FakeRunner()
        for url in ["", "https://github.com/acme/.."] {
            do {
                _ = try await ProjectOperations.cloneRepository(url: url, into: parent.url, runner: runner)
                XCTFail("expected invalidName for \(url.debugDescription)")
            } catch let error as ProjectOperationError {
                XCTAssertEqual(error, .invalidName(ProjectOperations.folderName(fromCloneURL: url)))
            }
        }
        XCTAssertEqual(runner.calls, [])
    }

    func testErrorsDescribeThemselvesInPlainEnglish() {
        XCTAssertEqual(ProjectOperationError.invalidName("").errorDescription, "The folder name is empty.")
        XCTAssertEqual(ProjectOperationError.invalidName("a/b").errorDescription,
                       "“a/b” can't be used as a folder name. Names can't be “.” or “..” and can't contain “/” or “:”.")
        XCTAssertEqual(ProjectOperationError.destinationExists("/tmp/app").errorDescription, "/tmp/app already exists. Choose another name or location.")
        XCTAssertEqual(ProjectOperationError.cloneFailed("fatal: not found").errorDescription, "git clone failed: fatal: not found")
        XCTAssertEqual(ProjectOperationError.initFailed("fatal: denied").errorDescription, "git init failed: fatal: denied")
        XCTAssertEqual(ProjectOperationError.unsupportedURL("ext::sh -c x").errorDescription,
                       "“ext::sh -c x” isn't a supported repository URL. Dev Desk clones only https, ssh, git and local-path URLs.")
    }

    func testCancelledCloneAndCreateRethrowCancellationInsteadOfAFailure() async throws {
        let parent = try TempGitRepo()
        let cancelled = ThrowingRunner(error: CancellationError())
        do {
            _ = try await ProjectOperations.cloneRepository(url: "https://github.com/acme/app.git", into: parent.url, runner: cancelled)
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
        do {
            _ = try await ProjectOperations.createProject(named: "Halted", in: parent.url, runner: cancelled)
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.url.appendingPathComponent("Halted").path))
    }
}
