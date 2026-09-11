/// Which queued tasks Auto starts next. Pure: the app passes the board, what is running and the limit, and starts what comes back.
public enum AutoScheduler {
    static let limits = 1...6

    /// Task ids to start now, in board order.
    public static func tasksToStart(board: [DeskTask], runningAgentTaskIDs: Set<String>, alreadyStarted: Set<String>,
                                    runningAgentsAcrossApp: Int, limit: Int) -> [String] {
        let clamped = min(max(limit, limits.lowerBound), limits.upperBound)
        let free = max(0, clamped - max(0, runningAgentsAcrossApp))
        let startable = board.lazy.filter { task in
            task.column == .queued && task.taskNumber != nil && task.noBranchNote == nil
                // With neither a branch nor a base ref the agent would open at the project root (rule 4), where Auto never starts one.
                && (task.branch?.isEmpty == false || task.baseRef != nil)
                && !runningAgentTaskIDs.contains(task.id) && !alreadyStarted.contains(task.id)
        }
        return Array(startable.prefix(free).map(\.id))
    }
}
