import XCTest
@testable import DeskCore

final class CommandRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    func testEchoReturnsStdout() async throws {
        let result = try await runner.run("echo", ["hello"], in: nil, timeout: 5)
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertTrue(result.succeeded)
    }

    func testFalseReturnsNonZeroStatus() async throws {
        let result = try await runner.run("false", [], in: nil, timeout: 5)
        XCTAssertEqual(result.status, 1)
        XCTAssertFalse(result.succeeded)
    }

    func testMissingPathProducesStderr() async throws {
        let result = try await runner.run("ls", ["/definitely-missing"], in: nil, timeout: 5)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        let result = try await runner.run("head", ["-c", "1048576", "/dev/zero"], in: nil, timeout: 10)
        XCTAssertEqual(result.stdout.utf8.count, 1_048_576)
    }

    func testSlowCommandThrowsTimedOut() async {
        do {
            _ = try await runner.run("sleep", ["5"], in: nil, timeout: 0.5)
            XCTFail("expected a timeout")
        } catch let error as CommandError {
            XCTAssertEqual(error, .timedOut(tool: "sleep", seconds: 0.5))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAChildKilledBySIGHUPDoesNotReadAsExitStatusOne() async throws {
        let result = try await runner.run("sh", ["-c", "kill -HUP $$"], in: nil, timeout: 5)
        XCTAssertEqual(result.status, 128 + SIGHUP, "a signal must not pass for git config's exit 1, which means \"not set\"")
    }

    func testMissingToolReportsToolMissing() async throws {
        let result = try await runner.run("no-such-tool-xyz", [], in: nil, timeout: 5)
        XCTAssertTrue(result.toolMissing)
    }
}
