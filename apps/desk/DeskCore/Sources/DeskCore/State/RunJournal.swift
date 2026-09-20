import Foundation

/// One run or session, as much of it as a next launch would need to say what was going on. It is written while
/// the run is live, not when it ends: the case it exists for is the app being killed, which runs no code.
///
/// `clean` is the whole distinction. A graceful end deletes the record and a graceful quit marks it clean;
/// nothing marks it clean when the app is force-quit or crashes, so an unclean record found at launch means
/// "this was live when the app died" without anything having to detect a crash.
public struct JournalRecord: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case backgroundRun
        case terminalSession
    }

    /// The run's own id — `job:findings:ab12cd34`, or a task id. The filename is a sanitised copy of it; this
    /// stays exact, because it is what a resume or a dismiss has to name.
    public let id: String
    public let kind: Kind
    public var title: String
    public var agent: String
    /// Where it ran. The registry spans projects, so a record without this could not be handed back to the
    /// window it belongs to.
    public var directory: String
    public var startedAt: Date
    /// Bumped on every write, so a recovered row can say how stale it is rather than only when it started.
    public var lastSeenAt: Date
    /// What a resume would continue. Nil until the agent reports one — and its absence is why Resume is not
    /// offered for every recovered run.
    public var sessionID: String?
    public var door: String?
    public var subject: String?
    /// `RunPermission` and `RunMode` raw values, so a resume runs under the grant the run was started with
    /// rather than under today's preference. Background runs only.
    public var permission: String?
    public var mode: String?
    /// The last state the app saw, already worded — the recovery row has no live state to ask.
    public var stateLabel: String
    /// The last lines the run wrote, newest last, capped like the live log: this is a row, not a transcript.
    public var logTail: [String]
    public var clean: Bool
    /// Terminal sessions only: what the session was, and where.
    public var purpose: String?
    public var branch: String?
    public var folderPath: String?
    /// The CLI the session was running (`claude`, `codex`), so a recovered row can offer that CLI's own resume.
    /// Nil for a plain shell, and for a record written before this was kept.
    public var executable: String?

    public init(id: String, kind: Kind, title: String, agent: String, directory: String,
                startedAt: Date = Date(), lastSeenAt: Date = Date(), sessionID: String? = nil,
                door: String? = nil, subject: String? = nil, permission: String? = nil, mode: String? = nil,
                stateLabel: String, logTail: [String] = [], clean: Bool = false,
                purpose: String? = nil, branch: String? = nil, folderPath: String? = nil,
                executable: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.agent = agent
        self.directory = directory
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.sessionID = sessionID
        self.door = door
        self.subject = subject
        self.permission = permission
        self.mode = mode
        self.stateLabel = stateLabel
        self.logTail = Array(logTail.suffix(BackgroundJob.logLimit))
        self.clean = clean
        self.purpose = purpose
        self.branch = branch
        self.folderPath = folderPath
        self.executable = executable
    }
}

/// A project's durable record of what was running in it, one JSON file per run under `.devdesk/runs/`.
///
/// This does **not** reverse ADR 0025: nothing here keeps a process alive past quit. What survives is the
/// knowledge of the run — enough for the next launch to say what was going on and offer to continue it. A file
/// per record rather than one index, because two windows and the app's own registry write here at the same
/// time and a shared index is the thing that loses a run when both rewrite it.
public final class RunJournal {
    private let directory: URL

    /// The runs folder inside a project. A sample project has no folder, so it gets no journal at all — the
    /// same nil that `ShellSessions` already treats as "nothing can run here".
    public convenience init(projectRoot: URL) {
        self.init(directory: projectRoot.appendingPathComponent(".devdesk/runs", isDirectory: true))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Replaces the record for this id. A journal write is bookkeeping beside a real run: it never throws,
    /// because a full disk or a read-only checkout must not be able to stop the run it is describing.
    public func write(_ record: JournalRecord) {
        guard let data = try? Self.encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Atomic: a record half-written when the app is killed is exactly the case this file exists for.
        try? data.write(to: url(for: record.id), options: .atomic)
    }

    /// A run that ended is history, not something to recover — the record goes. Absent is already the wanted state.
    public func clear(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// A graceful quit of a still-live run: the run is gone, but it ended on the app's terms, so the next
    /// launch must not present it as a crash.
    public func markClean(id: String) {
        guard var record = record(at: url(for: id)), !record.clean else { return }
        record.clean = true
        write(record)
    }

    /// What was live when the app died, newest first. Unreadable files are skipped: one corrupt record must
    /// not cost the user the others.
    public func recover() -> [JournalRecord] {
        all().filter { !$0.clean }
    }

    public func all() -> [JournalRecord] {
        files().compactMap(record(at:)).sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    /// Called once the recovery offer has been shown. Only clean records go: an unclean one is still waiting
    /// on the user, and deleting it would answer for them.
    public func purgeClean() {
        for url in files() where record(at: url)?.clean == true {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Ids carry `:` and can carry `/`, which is a path separator and not a filename. Only the name is
    /// sanitised; the id inside the JSON stays exact, because that is what resume and dismiss name.
    static func fileName(for id: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let safe = String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return (safe.isEmpty ? "record" : safe) + ".json"
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: id))
    }

    private func files() -> [URL] {
        let found = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return (found ?? []).filter { $0.pathExtension == "json" }
    }

    private func record(at url: URL) -> JournalRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(JournalRecord.self, from: data)
    }

    /// ISO dates and sorted keys: this file is read by a human debugging why a recovery row said what it said.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
