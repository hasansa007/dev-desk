import Foundation

/// `.devdesk/plan.json` — the order the developer put the milestones in on the Plan screen (ADR 0046). The top open
/// one is "Working now" and feeds the Board's Next up. Stored beside the work, like `BoardStages`, never on GitHub:
/// an order is the developer's, and expressing it as invented due dates would write fiction into the tracker.
/// Never throws — a full disk must not break the plan that is describing it.
public struct PlanOrder: Codable, Equatable, Sendable {
    public static let relativePath = ".devdesk/plan.json"
    public var titles: [String]

    public init(titles: [String] = []) { self.titles = titles }

    public static func url(in projectRoot: URL) -> URL { projectRoot.appendingPathComponent(relativePath) }

    /// Missing or unreadable reads as "no order": the old due-date / oldest rule then decides, and says so.
    public static func read(projectRoot: URL) -> PlanOrder {
        guard let data = try? Data(contentsOf: url(in: projectRoot)),
              let order = try? JSONDecoder().decode(PlanOrder.self, from: data) else { return PlanOrder() }
        return order
    }

    public func write(projectRoot: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let url = Self.url(in: projectRoot)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// `title` first, then every milestone in the order currently shown — so one move fixes the whole order and a
    /// later milestone does not jump ahead of ones the developer already arranged.
    public func movingToTop(_ title: String, shown: [String]) -> PlanOrder {
        var rest = (titles + shown).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        rest.removeAll { $0 == title }
        return PlanOrder(titles: [title] + rest)
    }

    /// `milestones` in this order: stored titles first (closed or renamed ones skipped), the rest as they came.
    public func apply<T>(_ milestones: [T], title: (T) -> String) -> [T] {
        let rank = Dictionary(titles.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return milestones.enumerated().sorted { a, b in
            (rank[title(a.element)] ?? Int.max, a.offset) < (rank[title(b.element)] ?? Int.max, b.offset)
        }.map(\.element)
    }
}
