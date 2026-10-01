import Foundation

/// `.devdesk/next-up.json` — the order the developer dragged Next up's cards into. Stored beside the work like
/// `PlanOrder`, never on GitHub: an order is the developer's, not a fact about the issues. A card it does not name
/// keeps the automatic place (`BoardOrder`) after every card it does. Never throws — a full disk must not break
/// the board describing it.
public struct CardOrder: Codable, Equatable, Sendable {
    public static let relativePath = ".devdesk/next-up.json"
    public var ids: [String]

    public init(ids: [String] = []) { self.ids = ids }

    public static func url(in projectRoot: URL) -> URL { projectRoot.appendingPathComponent(relativePath) }

    /// Missing or unreadable reads as "no order": the automatic one then stands.
    public static func read(projectRoot: URL) -> CardOrder {
        guard let data = try? Data(contentsOf: url(in: projectRoot)),
              let order = try? JSONDecoder().decode(CardOrder.self, from: data) else { return CardOrder() }
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

    /// `id` dropped before `target`, or at the end when there is none. The whole column as shown is stored, so
    /// one drag fixes every card's place and a card filed later does not jump ahead of ones already arranged.
    /// Ids no longer on screen (a started or closed card) are dropped rather than kept as stale places.
    public func moving(_ id: String, before target: String?, shown: [String]) -> CardOrder {
        var order = shown.filter { $0 != id }
        let index = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(id, at: index)
        return CardOrder(ids: order)
    }

    /// `tasks` in this order: named cards first, in sequence, the rest as they came.
    public func apply(_ tasks: [DeskTask]) -> [DeskTask] {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.enumerated().sorted { a, b in
            (rank[a.element.id] ?? Int.max, a.offset) < (rank[b.element.id] ?? Int.max, b.offset)
        }.map(\.element)
    }
}
