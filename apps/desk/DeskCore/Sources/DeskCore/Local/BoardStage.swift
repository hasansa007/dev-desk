import Foundation

/// The part of a card's lifecycle git cannot see: it has been judged ready, queued for a free agent
/// slot, or started with nothing committed yet. Everything after the first commit is git's (ADR 0011).
public enum BoardStage: String, Codable, Sendable, Hashable { case readyForDev, queued, inProgress }

/// `.devdesk/board.json` — the first board state Dev Desk *stores* rather than computes (ADR 0035,
/// partially reversing ADR 0011's "the board mirrors; it never decides"). The boundary that keeps
/// 0011's objection answered: git still wins for In progress (unmerged commits), Review (an open
/// non-draft pull request) and Done (merged) — `BoardBuilder` consults a stored stage only after
/// every git rule has declined, so the file can fill the gap before the first commit and never
/// contradict what git says. Machine-local bookkeeping, in the same never-throws shape as
/// `ProjectRunState`: a full disk must not crash the board that is describing it.
///
/// Keys are `DeskTask.id`: an issue card's id is its number as a string (`"42"`), a `docs/backlog/`
/// card's is `"local:<entry id>"`. A stage recorded under a `branch:`, `pr:` or `merged:` id is
/// ignored when the board is built — those are git's own cards.
public struct BoardStages: Codable, Equatable, Sendable {
    public static let relativePath = ".devdesk/board.json"
    public var stages: [String: BoardStage]

    public init(stages: [String: BoardStage] = [:]) {
        self.stages = stages
    }

    public static func url(in projectRoot: URL) -> URL { projectRoot.appendingPathComponent(relativePath) }

    /// A missing or unreadable file reads as "no stages", which is also the safe reading: every card
    /// falls back to what git and the milestone say, never to a guessed stage.
    public static func read(projectRoot: URL) -> BoardStages {
        guard let data = try? Data(contentsOf: url(in: projectRoot)),
              let stages = try? decoder.decode(BoardStages.self, from: data) else { return BoardStages() }
        return stages
    }

    /// Bookkeeping beside the work, never over it: like `ProjectRunState`, this never throws — the
    /// caller reads the file back when it must know whether the stage really landed.
    public func write(projectRoot: URL) {
        guard let data = try? Self.encoder.encode(self) else { return }
        let url = Self.url(in: projectRoot)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A copy with `taskID`'s stage set, or cleared when `stage` is nil — a card back in Backlog has
    /// no entry, rather than a fourth "backlog" stage the builder would have to know is a no-op.
    public func setting(_ stage: BoardStage?, for taskID: String) -> BoardStages {
        var copy = self
        copy.stages[taskID] = stage
        return copy
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
