import Foundation

/// How old a branch's tip is, and when that makes it stale. A branch with unmerged commits is In Progress by
/// git's rule (ADR 0011), and the rule has no idea whether anyone is still working on it — this is what lets the
/// board say so without overruling git.
public enum BranchAge {
    /// Past this, a branch is folded away rather than shown beside live work. Two weeks: long enough to cover a
    /// pause, short enough that a finished branch stops occupying the column.
    public static let staleAfter: TimeInterval = 14 * 24 * 60 * 60

    public static func isStale(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= staleAfter
    }

    /// "3 h ago", "8 d ago" — short, because it sits beside the commit count on a card.
    public static func label(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        let days = seconds / 86_400
        if days < 30 { return "\(days) d ago" }
        return "\(days / 30) mo ago"
    }
}
