/// Which cards a person's own Start has parked in Queued, and which of them a freed slot lets go now.
/// Pure, like `AutoScheduler`: the app passes the board, the free slot count and what is running, and
/// acts on what comes back — so a manual Start and Auto measure the same limit and cannot disagree.
public enum StartQueue {
    /// Whether pressing Start should park this card in Queued instead of running it: no slot free, and the
    /// card is one a start would move forward (unstarted, in Ready for dev or Queued). A Continue on work
    /// already in progress is never queued — it is not a new slot.
    public static func queuesInsteadOfStarting(_ task: DeskTask, freeSlots: Int) -> Bool {
        freeSlots <= 0 && (task.column == .readyForDev || task.column == .queued) && task.isUnstarted
    }

    /// Task ids to release from Queued now, in board order, at most `freeSlots` of them; a card already
    /// running is skipped — its slot is the one it already holds, not a place in line.
    public static func tasksToRelease(board: [DeskTask], freeSlots: Int, runningTaskIDs: Set<String>) -> [String] {
        Array(board.lazy.filter { $0.column == .queued && !runningTaskIDs.contains($0.id) }
            .prefix(max(0, freeSlots)).map(\.id))
    }

    /// The slots a pass may actually spend: the app's free slots minus the releases it is still waiting to see
    /// become live. A door run is counted by `LiveShells` only once its session is preparing, and the board
    /// reloads before that — without this, the pass that follows a release spends the same slot again.
    public static func spendableSlots(appFree: Int, releasedNotYetLive: Int) -> Int {
        max(0, appFree - max(0, releasedNotYetLive))
    }
}
