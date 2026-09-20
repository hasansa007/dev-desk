import DeskCore
import SwiftUI

/// What needs you across projects (ADR 0050). The project that needs you is drawn widest — Home is not a
/// dashboard of equal tiles, it is an answer to "where do I go now", and equal tiles do not answer that.
struct HomeScreen: View {
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headline
                    if let focus = workspace.focusContext {
                        ProjectFocusCard(workspace: workspace, context: focus, isFocus: true)
                        let rest = workspace.contextsInStripOrder.filter { $0.ref != focus.ref }
                        if !rest.isEmpty {
                            // Two to a row where there is room for two. `.flexible()` columns keep halving
                            // whatever they are given, so at a narrow window each card was handed ~130 pt and
                            // its words wrapped one letter to a line (2026-09-20, on screen).
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: ProjectFocusCard.minWidth), spacing: 14)],
                                      spacing: 14) {
                                ForEach(rest) { context in
                                    ProjectFocusCard(workspace: workspace, context: context, isFocus: false)
                                }
                            }
                        }
                    } else {
                        EmptyStateView(title: "No projects open",
                                       message: "Open one with the + at the bottom of the strip, or ⌘O.") {
                            Button("Open project") { workspace.isOpeningProject = true }
                                .buttonStyle(DeskButtonStyle(kind: .primary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.canvas)
        .navigationTitle("Dev Desk")
        .navigationSubtitle(workspace.refs.isEmpty ? "" : "\(workspace.refs.count) project\(workspace.refs.count == 1 ? "" : "s")")
        // Home carried no toolbar at all, so macOS gave it a short, pale title bar of its own and the
        // window's chrome changed height as you switched to it (2026-09-20, on screen). Open project moved
        // up here from the page header rather than being drawn in both places.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open project") { workspace.isOpeningProject = true }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .help("⌘O")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("dev desk").font(DeskFont.small.weight(.semibold)).foregroundStyle(DeskColor.ink)
            Text("home · \(workspace.refs.count) project\(workspace.refs.count == 1 ? "" : "s")")
                .font(DeskFont.small).foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 8)
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private var headline: some View {
        let waiting = workspace.waitingTotal
        let running = workspace.runningProjectCount
        return VStack(alignment: .leading, spacing: 6) {
            Text(waiting == 0 ? "Nothing needs you" : "\(waiting) thing\(waiting == 1 ? "" : "s") need\(waiting == 1 ? "s" : "") you")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(DeskColor.ink)
            Text(running == 0 ? "Nothing running" : "running in \(running) project\(running == 1 ? "" : "s")")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
        }
    }
}

/// One project on Home. The focus card carries the decision that is waiting and every live session; the rest
/// carry their counts and their sessions, because that is all you need to decide whether to go there.
private struct ProjectFocusCard: View {
    let workspace: Workspace
    let context: ProjectContext
    let isFocus: Bool

    /// Narrower than this and the card cannot hold a name, a path and a button on one line, so it takes its
    /// compact shape; it is also the grid's column floor, so a second card drops to the next row instead.
    static let minWidth: CGFloat = 320

    private var model: ProjectWindowModel { context.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The full header, or the compact one when the card is too narrow to hold it.
            ViewThatFits(in: .horizontal) {
                header(isCompact: false)
                header(isCompact: true)
            }
            if isFocus, let task = waitingTask { decision(task) }
            counts
            sessions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
                // The project that is stuck on you is outlined, the same way the run that needs you is.
                .strokeBorder(isFocus && context.waitingCount > 0 ? DeskColor.tone(.waiting).border : DeskColor.border)
        }
    }

    /// Compact drops the path — the name and a way in are what a card is for, and a squeezed path is the
    /// first thing that becomes unreadable.
    private func header(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            ProjectBadge(ref: context.ref, name: context.name, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.name)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if !isCompact {
                    Text([context.displayPath, context.branch].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(DeskFont.small)
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            Button("Open") { workspace.select(context.ref) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .fixedSize()
        }
    }

    /// The first card whose session has stopped to ask something. Dev Desk records THAT a session is waiting,
    /// not what it asked — the question is in the terminal — so Home names the task and takes you to it.
    private var waitingTask: DeskTask? {
        model.tasks.first { model.isWaiting($0) }
    }

    private func decision(_ task: DeskTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel("Needs a decision")
                Text(task.title).font(DeskFont.body).foregroundStyle(DeskColor.ink).lineLimit(1)
            }
            HStack(spacing: 8) {
                Button("Answer") { open(task, at: .terminals) }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                Button("Open the task") { open(task, at: .board) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.tone(.waiting).fill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.tone(.waiting).border)
        }
    }

    /// A flow, not an HStack: an HStack squeezes its children rather than wrapping, which turned
    /// "in progress" into one letter a line on a narrow card (2026-09-20, on screen).
    private var counts: some View {
        FlowLayout(spacing: 16) {
            count(model.workCounts(in: .inProgress).total, "in progress")
            count(model.workCounts(in: .review).total, "in review")
            count(model.workCounts(in: .readyForDev).total, "next up")
            if isFocus, let findings = model.findingsCount, findings > 0 {
                count(findings, "findings to decide")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text("\(value)").font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
            Text(label).font(DeskFont.small).foregroundStyle(DeskColor.mutedInk)
        }
        // One count is one thing: it wraps to the next row whole or not at all.
        .fixedSize()
    }

    @ViewBuilder private var sessions: some View {
        let live = SessionRow.all(in: model).filter(\.isLive)
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(live) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DeskColor.tone(model.waitingSessions.contains(row.id) ? .waiting : .running).dot)
                            .frame(width: 7, height: 7)
                        Text(row.title).font(DeskFont.small).foregroundStyle(DeskColor.secondaryInk)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func open(_ task: DeskTask, at destination: Destination) {
        workspace.select(context.ref)
        model.openTask(task.id)
        model.go(destination)
    }
}
