import DeskCore
import SwiftUI

/// Every card opens this: the task's identity at the top, its work in the middle, and what you can do to it
/// along the bottom. Its size is fixed (ADR 0021) — only the contents changed.
///
/// The footer is where actions live now. They were in the header beside the title, which put "Start task" and
/// "Close" in the same place a window's own controls sit, and left the destructive action nowhere.
struct TaskDialog: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"
    @Environment(\.terminals) private var terminals

    private var activity: TaskActivity? { model.activity(of: task) }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    meta
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                        .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
                }
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            }
            footer
        }
        .frame(width: DeskMetric.dialogWidth, height: DeskMetric.dialogHeight)
        .background(DeskColor.surface)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(task.title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let url = issueURL {
                    glyph("pencil", label: "Edit on GitHub") { NSWorkspace.shared.open(url) }
                }
                glyph("xmark", label: "Close") { model.dismissSheet() }
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Text(identifier)
                    .font(DeskFont.mono(12))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(DeskColor.border))
                StatusPill(badge: statusBadge, showsDot: false, verticalPadding: 4, horizontalPadding: 10)
                if isCheckedOut {
                    StatusPill(badge: StatusBadge(.info, "Checked out here"), showsDot: false,
                               verticalPadding: 4, horizontalPadding: 10)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(DeskColor.headerFill)
    }

    /// Where this task is edited: GitHub. The app does not edit an issue body, so the pencil goes to the place
    /// that does rather than pretending to be a field.
    private var isCheckedOut: Bool { task.branch != nil && task.branch == model.snapshot?.project.branch }

    private var issueURL: URL? {
        guard let number = task.issueNumber, let slug = model.snapshot?.slug else { return nil }
        return URL(string: "https://github.com/\(slug)/issues/\(number)")
    }

    private func glyph(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var identifier: String {
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
        HStack(spacing: 2) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Button { model.tab = tab } label: {
                    VStack(spacing: 0) {
                        Text(Self.tabTitle(tab))
                            .font(DeskFont.body)
                            .foregroundStyle(model.tab == tab ? DeskColor.ink : DeskColor.mutedInk)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        Rectangle()
                            .fill(model.tab == tab ? DeskColor.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
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
        HStack(spacing: 10) {
            if let delete = deleteBranch {
                Button(role: .destructive) { delete() } label: {
                    Label("Delete branch", systemImage: "trash")
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .help("Deletes the local branch only; a branch pushed to GitHub stays there")
            }
            Spacer(minLength: 8)
            if let blocked = primary.blockedReason {
                Text(blocked)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
            }
            Button(primary.title) { primary.run() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .regular))
                .disabled(primary.blockedReason != nil)
                .keyboardShortcut(.defaultAction)
            Button("Close") { model.dismissSheet() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
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
    private var primary: (title: String, blockedReason: String?, run: () -> Void) {
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
