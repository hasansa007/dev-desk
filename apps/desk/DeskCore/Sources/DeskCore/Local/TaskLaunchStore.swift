import Foundation

/// A project's pending launches, one JSON file per run under `.devdesk/launch/` (ADR 0036 decision 1).
///
/// It exists because a queued card used to store nothing: the column was the queue, and the agent and mode
/// were re-read from `UserDefaults` when a slot freed, so a card queued under Codex in Delegate started
/// under whatever the preferences said by then. The launch is written when the card is parked and read back
/// when it is released, so what was decided is what runs.
///
/// A file per launch rather than one index, for `RunJournal`'s reason: two windows can park cards at the
/// same time, and a shared index is the thing that loses one when both rewrite it.
public struct TaskLaunchStore {
    public static let relativeFolder = ".devdesk/launch"
    /// Where a launch handed to another app is written. NOT `relativeFolder`: a file there is what makes a card's
    /// next Start run without the sheet, and it can only name Claude or Codex, so a task started with another app
    /// would have its next Start quietly run Claude here.
    public static let startWithFolder = ".devdesk/start-with"

    private let directory: URL

    public init(projectRoot: URL, folder: String = TaskLaunchStore.relativeFolder) {
        self.directory = projectRoot.appendingPathComponent(folder, isDirectory: true)
    }

    /// Never throws: a full disk or a read-only checkout must not be able to stop the card being queued.
    /// A launch that fails to write is a card that falls back to today's behaviour, not a card that is lost.
    public func write(_ launch: TaskLaunch) {
        guard let data = try? Self.encoder.encode(launch) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: launch.id), options: .atomic)
    }

    /// nil when nothing was stored, which is also the safe reading: the caller rebuilds from today's values.
    public func read(id: String) -> TaskLaunch? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? Self.decoder.decode(TaskLaunch.self, from: data)
    }

    /// A launch that has been dispatched is history; the run's own record takes over from here.
    public func clear(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// What a launch is actually called on disk. An id carries a colon (`task:212`) and a filename must
    /// not, so anything printing the raw id names a file that is not there — the start sheet did.
    public static func fileName(for id: String) -> String { RunJournal.fileName(for: id) }

    public func url(for id: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: id))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
