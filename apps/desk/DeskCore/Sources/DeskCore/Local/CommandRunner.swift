import Foundation

public enum CommandTimeout {
    public static let git: TimeInterval = 15
    public static let gh: TimeInterval = 20
    public static let clone: TimeInterval = 300
}

public struct CommandResult: Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { status == 0 }
    /// `/usr/bin/env` exits 127 when the tool is not on PATH.
    public var toolMissing: Bool { status == 127 }
    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CommandError: Error, Equatable, LocalizedError {
    case launchFailed(String)
    case timedOut(tool: String, seconds: Double)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "Could not start the command: \(reason)"
        case .timedOut(let tool, let seconds): return "\(tool) did not finish within \(Int(seconds)) seconds."
        }
    }
}

public protocol CommandRunner {
    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult
}

/// Runs a tool from PATH, widened with the Homebrew and user bin directories a GUI app does not inherit.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runBlocking(tool, arguments, directory, timeout) })
            }
        }
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", "\(home)/bin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (existing + extra.filter { !existing.contains($0) }).joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        return env
    }

    private static func runBlocking(_ tool: String, _ arguments: [String], _ directory: URL?, _ timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.environment = environment()
        process.currentDirectoryURL = directory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw CommandError.launchFailed(error.localizedDescription) }

        // Both pipes drain concurrently, so output larger than the pipe buffer never blocks the child.
        var outData = Data()
        var errData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        readers.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); readers.leave() }

        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            if process.isRunning { timedOut.set(); process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        readers.wait()
        if timedOut.isSet { throw CommandError.timedOut(tool: tool, seconds: timeout) }
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

private final class Flag {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
