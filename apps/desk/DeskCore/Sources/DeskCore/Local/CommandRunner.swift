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
    let gate: CommandGate
    /// Extra variables merged over the inherited environment, e.g. GIT_ALLOW_PROTOCOL to restrict clone transports.
    let extraEnvironment: [String: String]

    public init() {
        gate = .shared
        extraEnvironment = [:]
    }

    public init(extraEnvironment: [String: String]) {
        gate = .shared
        self.extraEnvironment = extraEnvironment
    }

    init(gate: CommandGate, extraEnvironment: [String: String] = [:]) {
        self.gate = gate
        self.extraEnvironment = extraEnvironment
    }

    /// Holds a slot of the app-wide gate while the child runs; cancelling the task terminates the child and throws CancellationError.
    public func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        try await gate.acquire()
        do {
            let result = try await launch(tool, arguments, directory, timeout)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", "\(home)/bin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (existing + extra.filter { !existing.contains($0) }).joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        // Stops a partial clone from fetching a missing object mid-read, which would run its remote's uploadpack (git 2.44+).
        env["GIT_NO_LAZY_FETCH"] = "1"
        for (key, value) in extraEnvironment { env[key] = value }
        return env
    }

    private func launch(_ tool: String, _ arguments: [String], _ directory: URL?, _ timeout: TimeInterval) async throws -> CommandResult {
        let child = ChildProcess()
        let env = environment()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try Self.runBlocking(tool, arguments, directory, timeout, env, child) })
                }
            }
        } onCancel: {
            child.cancel()
        }
    }

    private static func runBlocking(_ tool: String, _ arguments: [String], _ directory: URL?, _ timeout: TimeInterval,
                                    _ environment: [String: String], _ child: ChildProcess) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        guard child.attach(process) else { throw CancellationError() }
        do { try process.run() } catch { throw CommandError.launchFailed(error.localizedDescription) }
        child.launched()

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
        if child.isCancelled { throw CancellationError() }
        if timedOut.isSet { throw CommandError.timedOut(tool: tool, seconds: timeout) }
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

/// Lets a cancelled task terminate its child; a process that has not launched yet is never terminated, only prevented.
private final class ChildProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// False when the task was cancelled before launch, so the caller must not start the process.
    func attach(_ process: Process) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.process = process
            return true
        }
    }

    func launched() { lock.withLock { if cancelled { terminateIfRunning() } } }

    func cancel() {
        lock.withLock {
            cancelled = true
            terminateIfRunning()
        }
    }

    private func terminateIfRunning() {
        if let process, process.isRunning { process.terminate() }
    }
}

private final class Flag {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
