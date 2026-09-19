import Foundation

/// `.devdesk/work.json` — this project's Work choices (ADR 0046 decision 7, Settings › Work). Beside the work like the
/// Plan's order, never in the repository's own configuration. Missing or unreadable reads as the defaults.
public struct WorkSettings: Codable, Hashable, Sendable {
    public static let relativePath = ".devdesk/work.json"

    /// What decides Working now: the top of the Plan (Move to top), or the milestone due soonest.
    public enum NextUpSource: String, Codable, CaseIterable, Hashable, Sendable { case plan, dueDate }

    public var nextUpFollows: NextUpSource = .plan
    /// How many merged items Done shows before "N more"; 0 shows them all.
    public var doneLimit: Int = 10
    /// Pull requests with no issue behind them — a report, a register edit — in Review.
    public var showsPullRequestsWithoutIssue: Bool = true

    public init(nextUpFollows: NextUpSource = .plan, doneLimit: Int = 10, showsPullRequestsWithoutIssue: Bool = true) {
        self.nextUpFollows = nextUpFollows
        self.doneLimit = doneLimit
        self.showsPullRequestsWithoutIssue = showsPullRequestsWithoutIssue
    }

    /// Tolerant: a file written by an older build, or edited by hand with a key missing, keeps the other keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextUpFollows = (try? c.decode(NextUpSource.self, forKey: .nextUpFollows)) ?? .plan
        doneLimit = max(0, (try? c.decode(Int.self, forKey: .doneLimit)) ?? 10)
        showsPullRequestsWithoutIssue = (try? c.decode(Bool.self, forKey: .showsPullRequestsWithoutIssue)) ?? true
    }

    public static func read(projectRoot: URL) -> WorkSettings {
        guard let data = try? Data(contentsOf: projectRoot.appendingPathComponent(relativePath)),
              let settings = try? JSONDecoder().decode(WorkSettings.self, from: data) else { return WorkSettings() }
        return settings
    }

    public func write(projectRoot: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let url = projectRoot.appendingPathComponent(Self.relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
