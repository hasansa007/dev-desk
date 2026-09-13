import DeskCore
import SwiftUI

/// Every session this window is running, side by side. The **only** host of a live terminal (ADR 0026): a
/// terminal is an NSView and can live in exactly one view hierarchy, so a second surface showing the same one
/// draws an empty frame while the first keeps it.
///
/// One, two or four up, because parallel work is the app's own premise — Auto runs up to three agents — and
/// that is the thing an edge panel and a modal both cannot do.
struct TerminalsScreen: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage("desk.terminals.columns") private var columns = 2

    private var rows: [SessionRow] { SessionRow.all(in: model) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                EmptyStateView(title: "Nothing running",
                               message: "Start a task from the board, or run a door from Findings, Ideation or Roadmap. Its terminal appears here.") {
                    Button("Go to the board") { model.go(.board) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary))
                }
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Terminals")
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            Text(rows.isEmpty ? "nothing running" : "\(rows.count) running")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 0)
            if rows.count > 1 {
                FlowLayout(spacing: 6) {
                    ForEach([1, 2, 4], id: \.self) { count in
                        FocusChip(title: "\(count) up", isOn: columns == count) { columns = count }
                    }
                }
            }
        }
        .screenHeaderBar()
    }

    private var grid: some View {
        let shown = rows
        let across = min(columns, max(shown.count, 1))
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: across), spacing: 12) {
                ForEach(shown) { row in
                    TerminalTile(model: model, row: row)
                        .frame(height: columns == 1 ? DeskMetric.terminalTileTallHeight : DeskMetric.terminalTileHeight)
                }
            }
            .padding(12)
        }
    }
}

/// One session in the grid: what it is, what it is doing, and its terminal.
private struct TerminalTile: View {
    let model: ProjectWindowModel
    let row: SessionRow
    @Environment(\.terminals) private var terminals

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(tone: row.isLive ? .running : .ended, pulses: row.isLive)
                Text(row.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if row.isLive {
                    Button("Stop") { terminals?.end(taskID: row.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(DeskColor.headerFill)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    @ViewBuilder private var pane: some View {
        switch row.kind {
        case .door(let run):
            ShellPane(sessions: model.sessions, id: run.id, folderNote: run.folderNote,
                      command: run.command, startTitle: "Start run")
        case .task(let task):
            ShellPane(sessions: model.sessions, id: task.id, branch: task.branch,
                      taskNumber: task.taskNumber, folderNote: task.noBranchNote, startTitle: "Start shell")
        }
    }
}

/// A door this window started, or a task's own session. Both are one session in one registry (ADR 0026).
struct SessionRow: Identifiable {
    enum Kind { case door(DoorRun), task(DeskTask) }

    let id: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let kind: Kind

    @MainActor
    static func all(in model: ProjectWindowModel) -> [SessionRow] {
        let doorIDs = Set(model.runs.runs.map(\.id))
        let doors = model.runs.runs.map { run in
            SessionRow(id: run.id, title: run.title,
                       subtitle: "\(run.agent) · \(RunsPanel.label(for: model.sessions.state(for: run.id)).label)",
                       isLive: model.sessions.state(for: run.id).isLive, kind: .door(run))
        }
        let tasks = model.sessions.activeTaskIDs.filter { !doorIDs.contains($0) }.compactMap { id -> SessionRow? in
            guard let task = model.task(id) else { return nil }
            return SessionRow(id: id, title: task.title,
                              subtitle: model.sessions.purpose(for: id) == .agent ? "Agent" : "Terminal",
                              isLive: model.sessions.state(for: id).isLive, kind: .task(task))
        }
        return doors + tasks
    }
}
