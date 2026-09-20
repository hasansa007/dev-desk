import DeskCore
import SwiftUI

/// One session in the dock: the same session Sessions would show, in a shorter frame. Its body is the very
/// panes that screen uses — `ShellPane` for anything with a shell, `JobPane` for a run that never had one —
/// so a terminal here behaves exactly as it does there and nothing about it is drawn twice.
///
/// The one-host rule (ADR 0026) still holds: a terminal is an NSView and lives in one view hierarchy at a
/// time. The dock is hidden on the Sessions tab precisely so the two surfaces never ask for the same one.
struct DockTile: View {
    let model: ProjectWindowModel
    let row: SessionRow
    /// Amber where the run is waiting on an answer, green while it works — the bar's chip says the same thing
    /// about the same session, so the two never disagree.
    let isWaiting: Bool
    let hide: () -> Void
    let openFullSize: () -> Void
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var answer = ""

    private var tone: StatusTone { isWaiting ? .waiting : (row.isLive ? .running : .ended) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DeskColor.divider).frame(height: 1)
            body(for: row.kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.surface)
    }

    /// The name, what it is doing, and the ✕ that puts the tile away. ✕ hides the tile and never stops the
    /// session: the dock is a place to watch a run from, so closing a window onto it must not end it.
    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(tone: tone, pulses: row.isLive && !isWaiting)
            Text(row.title)
                .font(DeskFont.small.weight(.semibold))
                .foregroundStyle(DeskColor.navInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.subtitle)
                .font(DeskFont.small)
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(action: openFullSize) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Opens this session full size in Sessions")
            .accessibilityLabel("Open \(row.title) in Sessions")
            Button(action: hide) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Puts this tile away. The session keeps running.")
            .accessibilityLabel("Hide \(row.title)")
        }
        .padding(.horizontal, 10)
        .frame(height: DockMetric.tileHeaderHeight)
        .background(DeskColor.headerFill)
    }

    @ViewBuilder private func body(for kind: SessionRow.Kind) -> some View {
        switch kind {
        case .job(let job):
            JobPane(job: job, answer: $answer) { jobs?.answer($0, to: job.id) }
        case .door(let run):
            ShellPane(sessions: model.sessions, id: run.id, folderNote: run.folderNote,
                      command: run.command, startTitle: "Start run", showsStop: false, showsStart: false)
        case .task(let task):
            ShellPane(sessions: model.sessions, id: task.id, branch: task.branch,
                      taskNumber: task.taskNumber, folderNote: task.noBranchNote,
                      startTitle: "Start shell", showsStop: false, showsStart: false)
        case .scratch, .projectRun:
            ShellPane(sessions: model.sessions, id: row.id, showsStop: false, showsStart: false)
        }
    }
}

/// The dock's own chrome, read off the Console prototype's `#dock`. These are not window edges or screen
/// headers, so they are not `DeskMetric`'s to carry.
enum DockMetric {
    static let barHeight: CGFloat = 34
    static let tileHeaderHeight: CGFloat = 28
    static let chipHeight: CGFloat = 24
    static let menuWidth: CGFloat = 340
}
