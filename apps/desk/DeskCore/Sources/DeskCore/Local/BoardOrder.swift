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
        [.backlog, .readyForDev, .queued].contains(column) ? tasks : newestFirst(tasks)
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
