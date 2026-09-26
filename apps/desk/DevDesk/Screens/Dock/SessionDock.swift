import DeskCore
import SwiftUI

/// The sessions of the project on screen, along the bottom of whatever tab you are on — several at once, side
/// by side, so watching a run does not mean leaving the board. Closed it is a bar naming what is live; open it
/// is those sessions as tiles, on an edge that drags.
///
/// It is scoped to this project (the model is), and its open state and height are kept per project
/// (`SessionDockState`), because one window now holds every project and the dock is a different answer in each.
///
/// Not on the Sessions tab: that tab is these same sessions full size, and a dock there would be the same
/// terminals asked for twice — which ADR 0026 says cannot be drawn anyway.
struct SessionDock: View {
    @Bindable var model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @Environment(\.terminals) private var terminals
    /// Where a new session's worktree would go, read here because opening one starts its shell at once.
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    private let dock = SessionDockState.shared
    @State private var showsMenu = false
    /// Rebuilt when the menu opens, not on every draw: reading the journal is a folder walk, and what it
    /// offers cannot change while the menu is up.
    @State private var offers: [ResumeOffer] = []

    private var rows: [SessionRow] { SessionRow.all(in: model, jobs: jobs) }
    private var isOpen: Bool { dock.isOpen(model.ref) }

    var body: some View {
        let rows = self.rows
        let ids = rows.map(\.id)
        VStack(spacing: 0) {
            // The dock's top edge is the handle, exactly as the Runs panel's was (ADR 0021): a hairline while
            // there is nothing to resize, a drag target the moment there is.
            if isOpen {
                EdgeResizer(edge: .bottom, size: heightBinding, range: DeskMetric.runsHeightRange)
            } else {
                Rectangle().fill(DeskColor.border).frame(height: 1)
            }
            bar(rows: rows, ids: ids)
            if isOpen {
                Rectangle().fill(DeskColor.divider).frame(height: 1)
                panes(rows: rows, ids: ids)
                    .frame(height: dock.height(for: model.ref))
            }
        }
        .background(DeskColor.strip)
        // ⌘] and ⌘[ while the dock is open: the next session along the bar, shown if it was not, and its
        // terminal takes the keys. The menu only offers the keys with the dock open, so a closed one never hears it.
        .onChange(of: model.sessionStep) { _, request in
            guard let request, isOpen else { return }
            model.sessionStep = nil
            let ids = self.rows.map(\.id)
            guard let id = request.target(from: dock.current(for: model.ref), among: ids) else { return }
            dock.step(to: id, for: model.ref, among: ids)
            terminals?.focus(taskID: id)
        }
    }

    private var heightBinding: Binding<Double> {
        Binding(get: { dock.height(for: model.ref) }, set: { dock.setHeight($0, for: model.ref) })
    }

    // MARK: - The bar

    /// Closed, this is the whole dock: what is live here, and the + that starts or continues something. A chip
    /// raises its tile and opens the dock with it, because clicking a session that is not shown can only mean
    /// "show me that one".
    private func bar(rows: [SessionRow], ids: [String]) -> some View {
        HStack(spacing: 4) {
            Button {
                dock.setOpen(!isOpen, for: model.ref)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DeskColor.mutedInk)
                    Text("sessions")
                        .font(DeskFont.small)
                        .foregroundStyle(DeskColor.navInk)
                    Text("\(rows.count)")
                        .font(DeskFont.small)
                        .foregroundStyle(DeskColor.mutedInk)
                }
                .padding(.horizontal, 6)
                .frame(height: DockMetric.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Closes the dock. Nothing stops." : "Opens the sessions running in this project")
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(rows) { row in
                        chip(row, ids: ids)
                    }
                    Spacer(minLength: 0)
                }
            }
            .scrollIndicators(.hidden)
            plus
            Spacer(minLength: 0)
            if isOpen {
                Text("\(dock.shown(for: model.ref, among: ids).count) shown side by side")
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
            }
            Button("Open in Sessions") { model.go(.terminals) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .help("The same sessions, full size, one at a time")
        }
        .padding(.horizontal, 10)
        .frame(height: DockMetric.barHeight)
        .background(DeskColor.headerFill)
    }

    private func chip(_ row: SessionRow, ids: [String]) -> some View {
        let isWaiting = model.waitingSessions.contains(row.id)
        let isShown = isOpen && dock.isShown(row.id, for: model.ref, among: ids)
        return Button {
            if isOpen {
                dock.toggle(row.id, for: model.ref, among: ids)
            } else {
                dock.raise(row.id, for: model.ref, among: ids)
                dock.setOpen(true, for: model.ref)
            }
        } label: {
            HStack(spacing: 7) {
                StatusDot(tone: isWaiting ? .waiting : (row.isLive ? .running : .ended),
                          pulses: row.isLive && !isWaiting, size: 6)
                Text(row.title)
                    .font(DeskFont.small)
                    .foregroundStyle(isShown ? DeskColor.ink : DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: DockMetric.chipHeight)
            .background(isShown ? DeskColor.neutralChipFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(row.subtitle)")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    // MARK: - The +

    /// One button with two halves: a new session, and — under a rule, not a heading — whatever can honestly be
    /// continued. A popover rather than a `Menu` because each row says what it would actually do, and that is
    /// a second line a menu item has nowhere to put.
    private var plus: some View {
        Button {
            offers = DockResume.offers(model: model, jobs: jobs, terminals: terminals,
                                       worktreeLocation: worktreeLocation, show: raise, reload: reloadOffers)
            showsMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
                .frame(width: 24, height: 22)
                .background(DeskColor.neutralChipFill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New session, or resume one that was left")
        .accessibilityLabel("New session or resume")
        .popover(isPresented: $showsMenu, arrowEdge: .top) { menu }
    }

    private var menu: some View {
        let refusal = model.sessions.startRefusal(for: .shell)
        return VStack(alignment: .leading, spacing: 2) {
            menuRow(title: "New session", subtitle: refusal ?? "A login shell at the project root",
                    tone: .running, isEnabled: refusal == nil) {
                open()
            }
            if !offers.isEmpty {
                Rectangle().fill(DeskColor.border).frame(height: 1).padding(.vertical, 4)
                SectionLabel("Resume")
                    .padding(.horizontal, 10)
                ForEach(offers) { offer in
                    menuRow(title: offer.title, subtitle: offer.subtitle, tone: offer.tone, isEnabled: true) {
                        offer.run()
                    }
                }
            }
        }
        .padding(6)
        .frame(width: DockMetric.menuWidth)
    }

    private func menuRow(title: String, subtitle: String, tone: StatusTone,
                         isEnabled: Bool, run: @escaping () -> Void) -> some View {
        Button {
            showsMenu = false
            run()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                StatusDot(tone: tone, pulses: false, size: 6)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DeskFont.secondary.weight(.semibold))
                        .foregroundStyle(DeskColor.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(DeskFont.small)
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    // MARK: - The tiles

    /// The shown sessions, side by side and equal, because the dock is for comparing what several runs are
    /// doing; the one you want to work in goes to Sessions, where it gets the whole screen.
    @ViewBuilder private func panes(rows: [SessionRow], ids: [String]) -> some View {
        let shown = dock.shown(for: model.ref, among: ids)
        let tiles = shown.compactMap { id in rows.first { $0.id == id } }
        if tiles.isEmpty {
            Text(rows.isEmpty ? "Nothing running here. Press + to start a session."
                              : "No session is shown. Pick one from the bar, or press + to start another.")
                .font(DeskFont.small)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(DeskColor.canvas)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(DeskColor.divider).frame(width: 1) }
                    DockTile(model: model, row: row, isWaiting: model.waitingSessions.contains(row.id),
                             isCurrent: dock.current(for: model.ref) == row.id) {
                        dock.hide(row.id, for: model.ref, among: ids)
                    } openFullSize: {
                        model.selectedSessionID = row.id
                        model.go(.terminals)
                    }
                    // Its own identity, not its place in the row: a tile that keeps the index of one that was
                    // hidden hosts the wrong terminal.
                    .id(row.id)
                }
            }
        }
    }

    // MARK: - Starting

    /// A new scratch session, in a tile, started here rather than offering a Start the developer never wanted
    /// to press twice — the same rule Sessions' "+" follows.
    private func open() {
        guard model.sessions.startRefusal(for: .shell) == nil, let terminals else { return }
        let id = model.newTerminal()
        raise(id)
        let location = worktreeLocation
        let title = "Terminal \(id.replacingOccurrences(of: "term:", with: ""))"
        Task {
            await model.sessions.start(taskID: id, branch: nil, taskNumber: nil,
                                       noBranchNote: nil, worktreeLocation: location, title: title)
            guard case .running(let folder) = model.sessions.state(for: id) else { return }
            terminals.start(taskID: id, folder: folder.url)
        }
    }

    /// The session just started or resumed takes a tile and the dock opens on it: it was asked for, so it is
    /// shown, and a closed dock would swallow the answer.
    private func raise(_ id: String) {
        dock.raise(id, for: model.ref, among: rows.map(\.id) + [id])
        dock.setOpen(true, for: model.ref)
    }

    private func reloadOffers() {
        offers = DockResume.offers(model: model, jobs: jobs, terminals: terminals,
                                   worktreeLocation: worktreeLocation, show: raise, reload: reloadOffers)
    }
}
