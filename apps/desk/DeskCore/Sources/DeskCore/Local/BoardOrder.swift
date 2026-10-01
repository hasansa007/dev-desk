import Foundation

/// One column's order: newest commit first, then every card git gave no date for, each keeping the place
/// `BoardBuilder` put it in. Sorting on a date alone drops that ordering, because Swift's sort is not stable
/// and a queue of undated cards compares equal at every pair.
public enum BoardOrder {
    /// Backlog, Ready for dev and Queued keep the order `BoardBuilder.orderNext` gave them — priority, slice,
    /// then the issue ignored longest, which is `dev.py`'s `order_next`. An unstarted card has no commit date
    /// to sort by, so `newestFirst` would only scramble that ranking. Every other column has no ranking of its
    /// own, so the newest commit leads.
    public static func inColumn(_ column: BoardColumn, _ tasks: [DeskTask]) -> [DeskTask] {
        [.backlog, .readyForDev, .queued].contains(column) ? byPriority(tasks) : newestFirst(tasks)
    }

    /// P0 first, unlabelled last, the builder's order kept within a priority. The ranking was assumed to arrive
    /// from `orderNext`, and on 2026-09-19 Next up showed a P3 above every P2 and P1 (ADR 0046).
    ///
    /// Local cards come after the local cards they need (ADR 0060), and a card that unblocks another ranks at that
    /// card's priority if it is higher, so a P1's prerequisites are not left behind every unrelated P2. Only edges
    /// between local cards count: an issue's order is what it was.
    public static func byPriority(_ tasks: [DeskTask]) -> [DeskTask] {
        func own(_ task: DeskTask) -> Int {
            task.priority.flatMap { TaskFilter.priorityOrder.firstIndex(of: $0) } ?? TaskFilter.priorityOrder.count
        }
        let index = Dictionary(tasks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        // needs[i]: the cards in this list that card i waits on.
        let needs = tasks.map { task -> [Int] in
            guard task.isLocalBacklog else { return [] }
            return task.dependencies.filter { $0.isBlocker }.compactMap { $0.taskID }
                .filter { $0.hasPrefix(DeskTask.localPrefix) }.compactMap { index[$0] }
        }
        guard needs.contains(where: { !$0.isEmpty }) else {
            return tasks.enumerated().sorted { (own($0.element), $0.offset) < (own($1.element), $1.offset) }.map(\.element)
        }
        // Each card's rank is the best of its own and of everything waiting on it, directly or not.
        var rank = tasks.map(own)
        var changed = true
        while changed {
            changed = false
            for (card, waitsOn) in needs.enumerated() {
                for needed in waitsOn where rank[card] < rank[needed] { rank[needed] = rank[card]; changed = true }
            }
        }
        // Kahn's: of the cards whose needs are placed, the best rank goes next. A cycle is placed by rank alone.
        var placed = [Bool](repeating: false, count: tasks.count)
        var result: [DeskTask] = []
        while result.count < tasks.count {
            let open = tasks.indices.filter { !placed[$0] }
            let ready = open.filter { needs[$0].allSatisfy { placed[$0] } }
            let next = (ready.isEmpty ? open : ready).min { (rank[$0], $0) < (rank[$1], $1) }!
            placed[next] = true
            result.append(tasks[next])
        }
        return result
    }

    public static func newestFirst(_ tasks: [DeskTask]) -> [DeskTask] {
        tasks.enumerated().sorted { left, right in
            switch (left.element.lastCommit, right.element.lastCommit) {
            case let (mine?, theirs?): return mine == theirs ? left.offset < right.offset : mine > theirs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.offset < right.offset
            }
        }.map(\.element)
    }
}
