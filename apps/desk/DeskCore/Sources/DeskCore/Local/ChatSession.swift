import Foundation
import Observation

/// One turn of a chat: who said it and what was said. The id is the message's own, so a list keeps its place
/// when an answer arrives beside it.
public struct ChatMessage: Identifiable, Hashable {
    public enum Role: Hashable { case user, assistant }

    public let id: UUID
    public let role: Role
    public let text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// A task's chat with an agent CLI. Every message is its own one-shot run of `claude -p` or `codex exec` —
/// the two non-interactive forms ADR 0030 allows, for a question asked where there is no terminal to watch —
/// started through the user's login shell in the task's folder, so it finds the same PATH and the same signed-in
/// tool a session started from the dock would (decision 14: the app never handles a credential).
///
/// Nothing is carried between turns: each run is a question and an answer, and the CLI is asked afresh. What to
/// run, which model to name and where to run it are all passed in — this stays free of preferences, as the rest
/// of DeskCore does.
@MainActor
@Observable
public final class ChatSession {
    public private(set) var messages: [ChatMessage] = []
    /// True from the moment a message is sent until its answer is in the list, which is what the input reads.
    public private(set) var isSending = false

    /// An agent reading a repository takes minutes, so this is `InsightsAgent`'s five, not a git read's fifteen
    /// seconds. A CLI that has not answered by then is ended, and said to have been.
    nonisolated static let timeout: TimeInterval = 300

    public init() {}

    /// Asks `agent` one question in `folder` and appends what it said. Empty input asks nothing, and a second
    /// send while one is in flight is ignored: one run per turn, so the transcript stays in the order it was said.
    public func send(_ text: String, agent: AgentKind, model: String?, folder: URL) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        messages.append(ChatMessage(role: .user, text: question))
        isSending = true
        let command = Self.command(agent: agent, model: model, message: question)
        let answer = await Self.reply(agent: agent, command: command, folder: folder)
        messages.append(ChatMessage(role: .assistant, text: answer))
        isSending = false
    }

    /// The CLI and its arguments, each an argument of its own — never a line of shell text, so a message
    /// carrying quotes or a newline is still one argument.
    static func command(agent: AgentKind, model: String?, message: String) -> [String] {
        var command: [String]
        switch agent {
        case .claude: command = ["claude", "-p", message]
        case .codex: command = ["codex", "exec", message]
        }
        if let model, !model.trimmingCharacters(in: .whitespaces).isEmpty {
            command += ["--model", model.trimmingCharacters(in: .whitespaces)]
        }
        return command
    }

    /// Runs the command off the main thread and turns the result into what the next bubble says. A failure is
    /// reported in the conversation rather than swallowed: the question was asked here, so its answer belongs here.
    private nonisolated static func reply(agent: AgentKind, command: [String], folder: URL) async -> String {
        let name = AgentLaunch.displayName(agent)
        guard let arguments = loginShellArguments(running: command) else {
            return "Dev Desk runs \(name) through zsh, bash or fish; your login shell is \(loginShellName)."
        }
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(arguments, in: folder))
            }
        }
        switch result {
        case .timedOut:
            return "\(name) didn't answer within \(Int(timeout) / 60) minutes, so the run was ended."
        case .launchFailed(let reason):
            return "\(name) couldn't be started: \(reason)"
        case .finished(let status, let stdout, let stderr):
            let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard status == 0 else {
                let detail = GitOutput.lastNonEmptyLine(stderr) ?? (output.isEmpty ? "it exited with status \(status)" : output)
                return "\(name) couldn't answer: \(detail)"
            }
            return output.isEmpty ? "\(name) finished without saying anything." : output
        }
    }

    private enum RunResult {
        case finished(status: Int32, stdout: String, stderr: String)
        case launchFailed(String)
        case timedOut
    }

    /// `/bin/sh` changes directory first and then execs the login shell, exactly as a task's terminal does:
    /// the folder, the shell and every word of the command stay arguments of their own, so none of them is
    /// ever read as script. Both pipes drain while the child runs, so an answer larger than a pipe buffer
    /// cannot block it, and stdin is /dev/null, so a CLI that wants to prompt fails plainly instead of hanging.
    private nonisolated static func run(_ arguments: [String], in folder: URL) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"cd -- "$1" && shift && exec "$@""#, "sh", folder.path, loginShellPath] + arguments
        process.currentDirectoryURL = folder
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .launchFailed(error.localizedDescription) }

        var outData = Data()
        var errData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        readers.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); readers.leave() }

        let expired = TimeoutFlag()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                expired.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        readers.wait()
        if expired.isSet { return .timedOut }
        let status = process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
        return .finished(status: status,
                         stdout: String(decoding: outData, as: UTF8.self),
                         stderr: String(decoding: errData, as: UTF8.self))
    }

    /// $SHELL, else /bin/zsh — the same shell a task's terminal runs, since it is the same PATH the answer needs.
    /// The app's `LoginShell` says this too, and cannot be read from here: DeskCore does not import the app.
    private nonisolated static var loginShellPath: String {
        ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    }

    private nonisolated static var loginShellName: String { (loginShellPath as NSString).lastPathComponent }

    /// What follows the shell's path to have it exec `command` as an interactive login shell, so a PATH set in
    /// ~/.zshrc applies as well as one set in ~/.zprofile. Nil for a shell other than zsh, bash or fish.
    private nonisolated static func loginShellArguments(running command: [String]) -> [String]? {
        switch loginShellName {
        case "zsh", "bash": return ["-l", "-i", "-c", #"exec "$0" "$@""#] + command
        case "fish": return ["-l", "-i", "-c", "exec $argv"] + command
        default: return nil
        }
    }
}

/// Set by the watchdog, read after the wait: one bool across two queues.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
