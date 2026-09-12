import Foundation

/// One column's order: newest commit first, then every card git gave no date for, each keeping the place
/// `BoardBuilder` put it in. Sorting on a date alone drops that ordering, because Swift's sort is not stable
/// and a queue of undated cards compares equal at every pair.
public enum BoardOrder {
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
