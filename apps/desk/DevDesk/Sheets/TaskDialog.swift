import DeskCore
import SwiftUI

/// A task's card, opened. The chrome — header, tabs, body, footer — is shared with every other card's dialog
/// and lives in `DialogChrome.swift`; what is here is only what a task puts in it.
struct TaskDialog: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"
    @Environment(\.terminals) private var terminals
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var confirmsRemoval = false

    private var activity: TaskActivity? { model.activity(of: task) }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            DialogBody { meta } content: { content }
            footer
        }
        .deskDialogFrame()
    }

    // MARK: - Header

    private var header: some View {
        DialogHeader(title: task.title, identifier: identifier, badges: badges, editURL: issueURL,
                     editHelp: task.isLocalBacklog ? "Open the file" : "Edit on GitHub",
                     close: model.dismissSheet)
    }

    private var badges: [StatusBadge] {
        var badges = [statusBadge]
        if isCheckedOut { badges.append(StatusBadge(.info, "Checked out here")) }
        return badges
    }

    /// Where this task is edited: GitHub. The app does not edit an issue body, so the pencil goes to the place
    /// that does rather than pretending to be a field.
    private var isCheckedOut: Bool { task.branch != nil && task.branch == model.snapshot?.project.branch }

    private var issueURL: URL? {
        // A local entry is edited where it lives: its file, in whatever opens markdown here.
        if let item = model.localBacklogItem(for: task) { return URL(fileURLWithPath: item.path) }
        guard let number = task.issueNumber, let slug = model.snapshot?.slug else { return nil }
        return URL(string: "https://github.com/\(slug)/issues/\(number)")
    }

    private var identifier: String {
        if let entry = task.localBacklogID { return "\(LocalBacklog.folder)/\(entry).md" }
        if !task.issueLabel.isEmpty { return task.issueLabel }
        return task.branch ?? task.id
    }

    /// What it is doing now outranks what column it sits in: a paused branch and a working one are not the same.
    private var statusBadge: StatusBadge {
        if let activity { return StatusBadge(.running, activity.label, pulses: true) }
        if task.column == .inProgress { return StatusBadge(.waiting, "Paused") }
        return task.headerBadge
    }

    // MARK: - Tabs

    private var tabs: some View {
        DialogTabBar(titles: TaskTab.allCases.map(Self.tabTitle), selected: Self.tabTitle(model.tab)) { title in
            if let tab = TaskTab.allCases.first(where: { Self.tabTitle($0) == title }) { model.tab = tab }
        }
    }

    static func tabTitle(_ tab: TaskTab) -> String {
        tab == .requirements ? "Overview" : tab.title
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .activity: ActivityTab(model: model, task: task)
        case .requirements: RequirementsTab(requirements: task.requirements)
        case .changes: ChangesTab(changes: task.changes)
        case .evidence: EvidenceTab(model: model, evidence: task.evidence)
        }
    }

    // MARK: - Meta

    private var meta: some View {
        HStack(spacing: 6) {
            PropertyChip("impact \(task.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            PropertyChip("complexity \(task.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            Spacer(minLength: 8)
            Text(ageLine)
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineLimit(1)
        }
    }

    private var ageLine: String {
        let age = task.lastCommit.map { "last commit \(BranchAge.label($0))" }
        let ahead = task.unmergedCount.map { "\($0) ahead" }
        return [age, ahead].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Footer

    private var footer: some View {
        DialogFooter(primary: DialogAction(title: primary.title, blockedReason: primary.blockedReason, run: primary.run),
                     secondary: localSecondary, close: model.dismissSheet) {
            if task.isLocalBacklog {
                Button(role: .destructive) { confirmsRemoval = true } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .help("Moves the file to the Trash")
                .confirmationDialog("Remove “\(task.title)” from docs/backlog/?", isPresented: $confirmsRemoval,
                                    titleVisibility: .visible) {
                    Button("Move to Trash", role: .destructive) {
                        model.dismissSheet()
                        Task { await model.removeLocalItem(task) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            if let delete = deleteBranch {
                Button(role: .destructive) { delete() } label: {
                    Label("Delete branch", systemImage: "trash")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .help("Deletes the local branch only; a branch pushed to GitHub stays there")
            }
        }
    }

    /// Filing on GitHub is only ever asked for, never done because a remote appeared (ADR 0027) — pointing
    /// origin at a fork, or signing gh in as someone else, is not consent to file fifteen issues there.
    private var localPrimary: (title: String, blockedReason: String?, run: () -> Void) {
        if let promotion, promotion.state.isLive {
            return ("Show the run", nil, {
                model.dismissSheet()
                model.selectedSessionID = promotion.id
                model.go(.terminals)
            })
        }
        if model.localBacklogReason != nil {
            // No tracker to file into, but the entry can still be worked on.
            return ("Start task", model.startBlockedReason(for: task, agent: defaultConnection), {
                model.startTask(task, agent: defaultConnection)
                model.dismissSheet()
            })
        }
        // A run that ended and left the entry here either failed or never reported a number: filing again is
        // offered, and named as again, so it is not mistaken for the first attempt.
        let triedBefore = promotion.map { !$0.state.isLive } ?? false
        return (triedBefore ? "File on GitHub again" : "File on GitHub",
                model.runBlockedReason(agent: defaultConnection), {
                    model.promoteLocalItem(task, jobs: jobs, agent: defaultConnection)
                })
    }

    /// Never the branch this project has checked out: git refuses to delete it, so the action could only ever
    /// produce "cannot delete branch … used by worktree at …". The board knows which branch that is.
    private var deleteBranch: (() -> Void)? {
        guard task.isBranchCard, let branch = task.branch,
              branch != model.snapshot?.project.branch else { return nil }
        return { model.present(.deleteBranch(branch)) }
    }

    /// One primary action, chosen by what this card actually is. A branch card has no issue for `/dev` to open,
    /// so offering "Start task" there was a button that could never fire — reported as "start is not working".
    /// The run promoting this local entry to GitHub, if one was started.
    private var promotion: BackgroundJob? {
        guard task.isLocalBacklog, let jobs, case .local(let path) = model.ref else { return nil }
        return jobs.job(subject: task.id, in: path)
    }

    /// A local entry with a tracker to go to offers both: filing it there, and starting it as it is.
    private var localSecondary: DialogAction? {
        guard task.isLocalBacklog, model.localBacklogReason == nil, activity == nil else { return nil }
        return DialogAction(title: "Start task", blockedReason: model.startBlockedReason(for: task, agent: defaultConnection)) {
            model.startTask(task, agent: defaultConnection)
            model.dismissSheet()
        }
    }

    private var primary: (title: String, blockedReason: String?, run: () -> Void) {
        if task.isLocalBacklog, activity == nil { return localPrimary }
        if activity != nil {
            return ("Open in Terminals", nil, {
                model.dismissSheet()
                model.selectedSessionID = task.id
                model.go(.terminals)
            })
        }
        if task.taskNumber != nil {
            return ("Start task", model.startBlockedReason(for: task, agent: defaultConnection), {
                model.startTask(task, agent: defaultConnection)
                model.dismissSheet()
            })
        }
        let choice = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? [])
        let blocked: String? = {
            if case .unavailable(let reason) = choice { return reason }
            return nil
        }()
        return ("Start agent", blocked, {
            if case .ready(let kind) = choice {
                _ = terminals?.startAgent(for: task, agent: kind, worktreeLocation: worktreeLocation)
            }
            model.dismissSheet()
            model.selectedSessionID = task.id
            model.go(.terminals)
        })
    }
}
