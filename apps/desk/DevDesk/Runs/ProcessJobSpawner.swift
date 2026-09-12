import AppKit
import DeskCore
import Foundation

/// Runs a background job as a plain child process and reports its output back on the main actor.
///
/// Not a pty: a headless run has no terminal and wants its JSONL whole, which is what `JobStream` reads. The
/// registry that owns the job is app-wide, so this outlives any one project window — and ends at quit, the same
/// escalation `LiveShells.endAllBeforeQuit` makes for shells (ADR 0025).
@MainActor
final class ProcessJobSpawner: JobSpawner {
    /// One running job. The exit is reported only once the pipe has reached EOF **and** the process has
    /// terminated: `claude -p` writes its `result` line — the one carrying the question — and exits at once, so
    /// tearing the reader down on termination drops exactly the line the feature depends on.
    private final class Channel {
        let process: Process
        var buffer = Data()
        var sawEOF = false
        var status: Int32?
        init(process: Process) { self.process = process }
    }

    private var channels: [String: Channel] = [:]
    private var terminateObserver: NSObjectProtocol?

    init() {
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                  object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ProcessJobSpawner.endAllBeforeQuit() }
        }
    }

    /// Every spawner's live processes, so the quit hook can reach them without capturing self in a notification
    /// that outlives it.
    private static var live: [ObjectIdentifier: ProcessJobSpawner] = [:]

    func spawn(id: String, launch: JobLaunch, directory: String,
               onLine: @escaping @MainActor (String) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) {
        Self.live[ObjectIdentifier(self)] = self
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launch.executable] + launch.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = ProcessRunner.widenedEnvironment()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        let channel = Channel(process: process)
        channels[id] = channel

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            Task { @MainActor in
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    ProcessJobSpawner.receiveEOF(id: id, spawner: self, onLine: onLine, onExit: onExit)
                } else {
                    ProcessJobSpawner.receive(chunk, id: id, spawner: self, onLine: onLine)
                }
            }
        }
        process.terminationHandler = { finished in
            Task { @MainActor in
                ProcessJobSpawner.receiveExit(finished.terminationStatus, id: id, spawner: self,
                                              onLine: onLine, onExit: onExit)
            }
        }

        do {
            try process.run()
        } catch {
            channels[id] = nil
            Task { @MainActor in
                onLine("Could not start \(launch.executable): \(error.localizedDescription)")
                onExit(127)
            }
        }
    }

    /// SIGTERM, then SIGKILL two seconds later to whatever ignored it — the escalation a shell gets.
    func stop(id: String) {
        guard let channel = channels[id], channel.process.isRunning else { return }
        let pid = channel.process.processIdentifier
        channel.process.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if self.channels[id]?.process.isRunning == true { kill(pid, SIGKILL) }
        }
    }

    /// A pipe delivers arbitrary byte chunks, not lines, and it splits multi-byte characters across reads.
    /// Decoding a chunk and dropping it when that fails loses a whole buffer on one em-dash, so lines are cut
    /// on the newline BYTE and only whole lines are decoded.
    private static func receive(_ chunk: Data, id: String, spawner: ProcessJobSpawner,
                                onLine: @escaping @MainActor (String) -> Void) {
        guard let channel = spawner.channels[id] else { return }
        channel.buffer.append(chunk)
        while let newline = channel.buffer.firstIndex(of: 0x0A) {
            let line = channel.buffer[channel.buffer.startIndex..<newline]
            channel.buffer = channel.buffer[channel.buffer.index(after: newline)...]
            if let text = String(data: line, encoding: .utf8) { onLine(text) }
        }
    }

    private static func receiveEOF(id: String, spawner: ProcessJobSpawner,
                                   onLine: @escaping @MainActor (String) -> Void,
                                   onExit: @escaping @MainActor (Int32) -> Void) {
        guard let channel = spawner.channels[id] else { return }
        channel.sawEOF = true
        // Whatever the run wrote without a trailing newline is still the last thing it said.
        if !channel.buffer.isEmpty, let rest = String(data: channel.buffer, encoding: .utf8),
           !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onLine(rest)
        }
        channel.buffer = Data()
        settle(id: id, spawner: spawner, onExit: onExit)
    }

    private static func receiveExit(_ status: Int32, id: String, spawner: ProcessJobSpawner,
                                    onLine: @escaping @MainActor (String) -> Void,
                                    onExit: @escaping @MainActor (Int32) -> Void) {
        guard let channel = spawner.channels[id] else { return }
        channel.status = status
        settle(id: id, spawner: spawner, onExit: onExit)
    }

    private static func settle(id: String, spawner: ProcessJobSpawner, onExit: @escaping @MainActor (Int32) -> Void) {
        guard let channel = spawner.channels[id], channel.sawEOF, let status = channel.status else { return }
        spawner.channels[id] = nil
        onExit(status)
    }

    /// Quit holds the main queue, so no timer fires: SIGTERM everything, reap for at most two seconds in all,
    /// then SIGKILL what is left — otherwise a run mid-tool-call outlives the app, which is the detached shape
    /// ADR 0025 rejected.
    private static func endAllBeforeQuit() {
        let processes = live.values.flatMap { $0.channels.values.map(\.process) }.filter(\.isRunning)
        processes.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while processes.contains(where: \.isRunning), Date() < deadline { usleep(20_000) }
        processes.filter(\.isRunning).forEach { kill($0.processIdentifier, SIGKILL) }
    }
}
