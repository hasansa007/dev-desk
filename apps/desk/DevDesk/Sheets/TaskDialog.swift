import DeskCore
import SwiftUI

/// A task's card, opened. The chrome — header, tabs, body, footer — is shared with every other card's dialog
/// and lives in `DialogChrome.swift`; what is here is only what a task puts in it.
struct TaskDialog: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    /// Filing runs in the background, so it uses the Background runs setting rather than the default connection.
    private var backgroundConnection: String {
        BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
    }
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @Environment(\.terminals) private var terminals
    @Environment(\.openURL) private var openURL
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var confirmsRemoval = false
    @State private var confirmsApproval = false
    @State private var confirmsWorktreeRemoval = false
    /// The dialog's edit, open only for an issue: a local entry is still edited in its own file.
    @State private var edit: TaskEdit?



    private var activity: TaskActivity? { model.activity(of: task) }

    private var changedFileCount: Int {
        if case .available(let changes) = task.changes { return changes.files.count }
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if edit == nil {
                tabs
                DialogBody { meta } content: { content }
            } else {
                DialogBody { EmptyView() } content: { editForm }
            }
            footer
        }
        .deskDialogFrame()
    }

    // MARK: - Header

    private var header: some View {
        DialogHeader(title: task.title, identifier: identifier, badges: badges, editURL: issueURL,
                     edit: task.issueNumber == nil ? nil : { beginEdit() },
                     editHelp: task.isLocalBacklog ? "Open the file" : "Edit this issue",
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

    // MARK: - Edit

    /// The issue as fields: its title, its two ratings and its body. Saved with one `gh issue edit`, then the board
    /// reloads, so what is shown afterwards is what GitHub has — never only what was typed.
    @ViewBuilder private var editForm: some View {
        if let edit {
            VStack(alignment: .leading, spacing: 14) {
                row("Title") {
                    TextField("What needs doing", text: Binding(get: { edit.title }, set: { self.edit?.title = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                row("Impact") { ratingPicker(get: { edit.impact }, set: { self.edit?.impact = $0 }) }
                row("Complexity") { ratingPicker(get: { edit.complexity }, set: { self.edit?.complexity = $0 }) }
                if !model.openMilestones.isEmpty {
                    row("Milestone") {
                        Picker("", selection: Binding(get: { edit.milestone }, set: { self.edit?.milestone = $0 })) {
                            Text("None").tag("")
                            // The one it is in may be closed and so absent from the open list; it is still where it is.
                            ForEach(milestoneChoices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 360, alignment: .leading)
                    }
                }
                row("Description") {
                    TextField("What it is and why", text: Binding(get: { edit.body }, set: { self.edit?.body = $0 }),
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(DeskFont.mono(12))
                        .lineLimit(12...30)
                }
            }
        }
    }

    private var milestoneChoices: [String] {
        let open = model.openMilestones
        guard let current = task.milestone, !current.isEmpty, !open.contains(current) else { return open }
        return [current] + open
    }

    /// The Add Task sheet's row: one label column, so a task reads the same whether it is being made or changed.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).foregroundStyle(DeskColor.secondaryInk).frame(width: 130, alignment: .trailing)
            content()
        }
    }

    private func ratingPicker(get: @escaping () -> String, set: @escaping (String) -> Void) -> some View {
        TaskRatings.picker(selection: Binding(get: get, set: set))
    }

    private func beginEdit() {
        edit = TaskEdit(title: task.title,
                        body: task.requirements.value?.body ?? "",
                        impact: task.impact ?? TaskRatings.none,
                        complexity: task.complexity ?? TaskRatings.none,
                        milestone: task.milestone ?? "")
    }

    private func saveEdit() {
        guard let edit else { return }

        self.edit = nil
        Task {
            await model.saveEdit(task, title: edit.title, body: edit.body,
                                 impact: TaskRatings.value(edit.impact), complexity: TaskRatings.value(edit.complexity),
                                 milestone: edit.milestone)
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

    @ViewBuilder private var footer: some View {
        if let edit {
            // Close still closes the dialog; Cancel only leaves the form, so a mistyped edit is not also a lost dialog.
            DialogFooter(primary: DialogAction(title: "Save changes",
                                               blockedReason: edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                   ? "An issue needs a title." : nil,
                                               run: { saveEdit() }),
                         secondary: DialogAction(title: "Cancel", run: { self.edit = nil }),
                         close: model.dismissSheet)
        } else {
            readingFooter
        }
    }

    private var readingFooter: some View {
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
            if task.isFinishedReport, !task.isMerged, let branch = task.branch {
                Color.clear.frame(width: 0, height: 0)
                    .confirmationDialog("Approve this report?", isPresented: $confirmsApproval, titleVisibility: .visible) {
                        Button("Merge and push") {
                            model.dismissSheet()
                            Task { await model.approveReport(task) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(ReportMerge.confirmation(branch: branch, base: ReportMerge.originBase(task.baseRef) ?? "the base branch",
                                                      commits: task.unmergedCount, files: changedFileCount))
                    }
            }
            if task.column == .done, let worktree = task.worktreePath {
                Button { confirmsWorktreeRemoval = true } label: {
                    Label("Remove worktree", systemImage: "folder.badge.minus")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .disabled(model.isWritingTracker)
                .help("Removes \(worktree) and the merged local branch; git refuses if the folder has changes")
                .confirmationDialog("Remove this worktree?", isPresented: $confirmsWorktreeRemoval, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        model.dismissSheet()
                        Task { await model.removeWorktree(task) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\(worktree) and the local branch \(task.branch ?? ""). Its work is merged. git keeps both if the folder has uncommitted or untracked files, or the branch has commits the base lacks.")
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
                model.runBlockedReason(agent: backgroundConnection), {
                    model.promoteLocalItem(task, jobs: jobs, agent: backgroundConnection)
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
        // A merged card is history — never "Start task". Surface its PR link when it carries one.
        if task.isMerged {
            if case .openURL(let url, let title) = task.nextAction {
                return (title, nil, { openURL(url) })
            }
            return ("Merged", "This work is merged.", {})
        }
        if task.isFinishedReport {
            return ("Approve & merge", model.isWritingTracker ? "A write is already running." : nil, { confirmsApproval = true })
        }
        if task.taskNumber != nil {
            return ("Start task", model.startBlockedReason(for: task, agent: defaultConnection), {
                model.startTask(task, agent: defaultConnection)
                model.dismissSheet()
            })
        }
        let choice = AgentChoice.current(for: model.ref, connections: model.snapshot?.connections ?? [],
                                   terminalAgents: model.snapshot?.terminalAgents ?? [])
        let blocked: String? = {
            if case .unavailable(let reason) = choice { return reason }
            return nil
        }()
        return ("Start agent", blocked, {
            if case .ready(let kind) = choice {
                _ = terminals?.startAgent(for: task, agent: kind, worktreeLocation: worktreeLocation,
                                          mode: RunModeChoice.current(for: model.ref))
            }
            model.dismissSheet()
            model.selectedSessionID = task.id
            model.go(.terminals)
        })
    }
}

/// One issue's fields while it is being edited; nil when the dialog is only reading.
private struct TaskEdit {
    var title: String
    var body: String
    var impact: String
    var complexity: String
    /// "" is no milestone, which is also what the None row means.
    var milestone: String
}
