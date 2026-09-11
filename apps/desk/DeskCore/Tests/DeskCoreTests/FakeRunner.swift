import Foundation
import XCTest
@testable import DeskCore

/// Responses keyed by "<tool> <args joined by space>"; anything unscripted fails with "unscripted".
final class FakeRunner: CommandRunner {
    struct Call: Equatable {
        let key: String
        let directory: URL?
        let timeout: TimeInterval
    }

    private let lock = NSLock()
    private var responses: [String: CommandResult]
    private var recorded: [Call] = []

    init(_ responses: [String: CommandResult] = [:]) { self.responses = responses }

    var calls: [Call] { lock.withLock { recorded } }
    var keys: [String] { calls.map(\.key) }

    func script(_ key: String, _ result: CommandResult) { lock.withLock { responses[key] = result } }

    /// The recorded key for a hardened git read: the hardening flags sit between "git" and the subcommand.
    static func gitRead(_ subcommand: String) -> String {
        (["git"] + GitCommand.readFlags + subcommand.split(separator: " ").map(String.init)).joined(separator: " ")
    }

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        let key = ([tool] + arguments).joined(separator: " ")
        return lock.withLock {
            recorded.append(Call(key: key, directory: directory, timeout: timeout))
            return responses[key] ?? CommandResult(status: 1, stdout: "", stderr: "unscripted")
        }
    }
}

extension CommandResult {
    static func ok(_ stdout: String = "") -> CommandResult { CommandResult(status: 0, stdout: stdout, stderr: "") }
    static func failed(_ status: Int32 = 1, stderr: String = "") -> CommandResult { CommandResult(status: status, stdout: "", stderr: stderr) }
}

/// Throws the same error from every call, standing in for a timeout or a cancelled task.
struct ThrowingRunner: CommandRunner {
    let error: Error

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        throw error
    }
}

final class FakeRunnerTests: XCTestCase {
    func testScriptedCallReturnsItsResultAndIsRecorded() async throws {
        let runner = FakeRunner(["git rev-parse --show-toplevel": .ok("/repo\n")])
        let result = try await runner.run("git", ["rev-parse", "--show-toplevel"], in: nil, timeout: CommandTimeout.git)
        XCTAssertEqual(result.stdout, "/repo\n")
        XCTAssertEqual(runner.keys, ["git rev-parse --show-toplevel"])
        XCTAssertEqual(runner.calls.first?.timeout, CommandTimeout.git)
    }

    func testUnscriptedCallFailsWithUnscripted() async throws {
        let runner = FakeRunner()
        let result = try await runner.run("gh", ["auth", "status"], in: nil, timeout: CommandTimeout.gh)
        XCTAssertEqual(result, CommandResult(status: 1, stdout: "", stderr: "unscripted"))
    }
}
