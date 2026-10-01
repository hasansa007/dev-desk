/// Which Ready for dev tasks Auto starts next. Pure: the app passes the board, what is running and the limit, and starts what comes back.
public enum AutoScheduler {
    /// How many agents may run at once, across the app. Settings → Execution offers exactly this range.
    public static let limits = 1...10
    public static let defaultLimit = 5

    /// Task ids to start now, in the order given — the app passes Next up in its hand order. Ready for dev is where planned work sits now (ADR 0035);
    /// Queued means "waiting for a free agent slot", and `StartQueue` is what fills and releases it.
    /// `waiting` holds the cards whose blocker is still open (ADR 0046, 0060): they are passed over, not counted,
    /// so the work that does not depend on them takes the slots, and they start on the pass after their blocker is done.
    public static func tasksToStart(board: [DeskTask], runningAgentTaskIDs: Set<String>, alreadyStarted: Set<String>,
                                    waiting: Set<String> = [], runningAgentsAcrossApp: Int, limit: Int) -> [String] {
        let clamped = min(max(limit, limits.lowerBound), limits.upperBound)
        let free = max(0, clamped - max(0, runningAgentsAcrossApp))
        let startable = board.lazy.filter { task in
            // A local card (ADR 0058) has no number and needs none: Start hands `/dev` its file. Where it runs is the
            // Start's to resolve, as it is for a card started by hand, so a missing base ref no longer holds it back.
            task.column == .readyForDev && (task.taskNumber != nil || task.isLocalBacklog) && task.noBranchNote == nil
                && !runningAgentTaskIDs.contains(task.id) && !alreadyStarted.contains(task.id) && !waiting.contains(task.id)
        }
        return Array(startable.prefix(free).map(\.id))
    }
}
