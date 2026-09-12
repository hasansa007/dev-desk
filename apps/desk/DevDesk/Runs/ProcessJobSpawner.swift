import AppKit
import DeskCore
import Foundation

/// Runs a background job as a plain child process and reports its output back on the main actor.
///
/// Not a pty: a headless run has no terminal and wants its JSONL whole, which is what `JobStream` reads. The
/// registry that owns the job is app-wide, so this outlives any one project window — and ends at quit, the same
/// bargain `LiveShells.endAllBeforeQuit` makes for shells (ADR 0025).
final class ProcessJobSpawner: JobSpawner {
    private var processes: [String: Process] = [:]
    private var buffers: [String: String] = [:]
    private var terminateObserver: NSObjectProtocol?

    init() {
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.endAllBeforeQuit()
        }
    }

    func spawn(id: String, launch: JobLaunch, directory: String,
               onLine: @escaping @MainActor (String) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launch.executable] + launch.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = ProcessRunner.widenedEnvironment()

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        buffers[id] = ""
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.take(text, id: id, onLine: onLine) }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.flush(id: id, onLine: onLine)
                self?.processes[id] = nil
                self?.buffers[id] = nil
                onExit(finished.terminationStatus)
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            Task { @MainActor in
                onLine("Could not start \(launch.executable): \(error.localizedDescription)")
                onExit(127)
            }
        }
    }

    /// SIGTERM, then SIGKILL two seconds later to whatever ignored it — the same escalation a shell gets.
    func stop(id: String) {
        guard let process = processes[id], process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if self.processes[id]?.isRunning == true { kill(pid, SIGKILL) }
        }
    }

    /// A pipe delivers arbitrary chunks, not lines; a JSONL reader given half an object parses nothing.
    @MainActor
    private func take(_ text: String, id: String, onLine: @escaping @MainActor (String) -> Void) {
        var buffer = (buffers[id] ?? "") + text
        while let newline = buffer.firstIndex(of: "\n") {
            onLine(String(buffer[buffer.startIndex..<newline]))
            buffer = String(buffer[buffer.index(after: newline)...])
        }
        buffers[id] = buffer
    }

    /// Whatever the run wrote without a trailing newline is still the last thing it said.
    @MainActor
    private func flush(id: String, onLine: @escaping @MainActor (String) -> Void) {
        if let rest = buffers[id], !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onLine(rest) }
    }

    private func endAllBeforeQuit() {
        processes.values.filter(\.isRunning).forEach { $0.terminate() }
    }
}
