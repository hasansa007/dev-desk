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
    @State private var expandedID: String?
    @State private var hasChosen = false

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
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DeskColor.canvas)
        .onAppear(perform: syncExpansion)
        .onChange(of: model.selectedSessionID) { _, id in
            guard let id else { return }
            hasChosen = true
            expandedID = id
        }
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
        }
        .screenHeaderBar()
    }

    /// An accordion, not a grid. Two terminals at half height are two terminals you cannot read, and only the
    /// expanded one hosts its view — which is the one-host rule (ADR 0026) enforced by the layout rather than
    /// remembered by whoever adds the next surface.
    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    TerminalTile(model: model, row: row, isExpanded: expandedID == row.id) {
                        hasChosen = true
                        expandedID = expandedID == row.id ? nil : row.id
                    }
                }
            }
            .padding(12)
        }
    }

    /// Which row is open. Arriving from a card or a door start lands on that session; after that it is whatever
    /// you last clicked, including nothing.
    ///
    /// It has to be real state. Deriving it as `selection ?? firstLive` meant collapsing a row set the selection
    /// to nil and the fallback immediately re-opened the same row — the chevron did nothing, every time.
    private func syncExpansion() {
        guard !hasChosen else { return }
        expandedID = model.selectedSessionID ?? rows.first(where: \.isLive)?.id ?? rows.first?.id
    }
}

/// One session in the grid: what it is, what it is doing, and its terminal.
private struct TerminalTile: View {
    let model: ProjectWindowModel
    let row: SessionRow
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.terminals) private var terminals

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The expander is its own button and Stop is its sibling. A tap gesture on the whole row
                // swallows the clicks of the buttons inside it — the same way the card's outer Button ate its
                // own Start, and reported the same way: "stop is not working".
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(DeskColor.mutedInk)
                            .frame(width: 12)
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(row.title)")
                if row.isLive {
                    // The only Stop: the pane's own "End shell" is suppressed, and a collapsed row can reach this.
                    Button("Stop") { terminals?.end(taskID: row.id) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(DeskColor.headerFill)
            if isExpanded {
                Rectangle().fill(DeskColor.divider).frame(height: 1)
                pane
                    .frame(maxWidth: .infinity, minHeight: DeskMetric.terminalTileTallHeight,
                           maxHeight: DeskMetric.terminalTileTallHeight)
            }
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    @ViewBuilder private var pane: some View {
        switch row.kind {
        case .door(let run):
            ShellPane(sessions: model.sessions, id: run.id, folderNote: run.folderNote,
                      command: run.command, startTitle: "Start run", showsStop: false)
        case .task(let task):
            ShellPane(sessions: model.sessions, id: task.id, branch: task.branch,
                      taskNumber: task.taskNumber, folderNote: task.noBranchNote, startTitle: "Start shell",
                      showsStop: false)
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
                       subtitle: "\(run.agent) · \(RunLabel.label(for: model.sessions.state(for: run.id)).label)",
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
