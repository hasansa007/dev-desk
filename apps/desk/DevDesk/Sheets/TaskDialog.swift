import DeskCore
import SwiftUI

/// Every card opens this. Selecting a card never leaves the board: the task's issue, its activity, its diff,
/// its evidence, its terminal and its agent all live here.
struct TaskDialog: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    private var activity: TaskActivity? { model.activity(of: task) }
    private var isRunning: Bool { activity != nil }

    var body: some View {
        SheetChrome(title: title, confirmTitle: confirmTitle,
                    confirmDisabled: !isRunning && blockedReason != nil,
                    cancelTitle: "Close",
                    onCancel: model.dismissSheet, onConfirm: confirm) {
            VStack(alignment: .leading, spacing: 12) {
                facts
                if let activity {
                    NoticeBanner(tone: .running, title: runningTitle(activity),
                                 message: runningMessage(activity), style: .compact) {
                        Button(confirmTitle) { confirm() }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                } else if let blockedReason {
                    NoticeBanner(tone: .neutral, title: "Nothing to start yet", message: blockedReason, style: .compact)
                }
                tabs
                content
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            }
        }
    }

    private var title: String {
        task.issueLabel.isEmpty ? task.title : "\(task.issueLabel) · \(task.title)"
    }

    private var facts: some View {
        HStack(spacing: 8) {
            StatusPill(badge: task.headerBadge, showsDot: false, verticalPadding: 2, horizontalPadding: 8)
            if task.issueNumber != nil {
                PropertyChip("impact \(task.impact ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
                PropertyChip("complexity \(task.complexity ?? "—")", fill: DeskColor.neutralChipFill2, verticalPadding: 1)
            }
            Text(task.branchLine)
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Button {
                    model.tab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(Self.tabTitle(tab))
                            .font(DeskFont.body)
                            .foregroundStyle(model.tab == tab ? DeskColor.ink : DeskColor.mutedInk)
                            .padding(.vertical, 6)
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
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    static func tabTitle(_ tab: TaskTab) -> String {
        switch tab {
        case .requirements: return "Overview"
        // "Shell" and "Agent" are two words for one terminal; only the driver differs, so name the driver.
        case .shell: return "Terminal"
        default: return tab.title
        }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .activity: ActivityTab(model: model, task: task)
        case .requirements: RequirementsTab(requirements: task.requirements)
        case .changes: ChangesTab(changes: task.changes)
        case .evidence: EvidenceTab(model: model, evidence: task.evidence)
        // The dock these two lived in is gone; they keep their own worktree and their own trust note (ADRs 0017, 0018).
        case .shell:
            pane(caption: "You type the commands. A login shell in this task's folder, as Terminal would open it.") {
                ShellPane(sessions: model.shellSessions, id: task.id, branch: task.branch,
                          taskNumber: task.taskNumber, folderNote: task.noBranchNote)
            }
        case .agent:
            pane(caption: "\(defaultConnection) types them. The same folder, driven by the pipeline's prompt; it stops at each gate and asks you here.") {
                AgentPane(model: model, task: task)
            }
        }
    }

    /// The two terminal tabs differ only in who is typing, so each says so above its own pane.
    private func pane<Content: View>(caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(caption)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .frame(minHeight: 330)
                .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        }
    }

    private var confirmTitle: String {
        switch activity {
        case .none: return "Start task"
        case .run: return "View run"
        case .shell: return "Open the terminal"
        case .agent: return "Open the agent"
        }
    }

    private func runningTitle(_ activity: TaskActivity) -> String {
        switch activity {
        case .run: return "A door is running for this task"
        case .shell: return "This task has a terminal open"
        case .agent: return "An agent is working on this task"
        }
    }

    private func runningMessage(_ activity: TaskActivity) -> String {
        switch activity {
        case .run: return "Its output is in the Runs panel. Ending it there stops the run."
        case .shell: return "It is in this dialog's Terminal tab, in the task's own folder."
        case .agent: return "It is in this dialog's Agent tab. Stopping it there ends the session."
        }
    }

    private var blockedReason: String? { model.startBlockedReason(for: task, agent: defaultConnection) }

    /// Live: go to whichever surface is carrying the work. Idle: start `/dev #N`, which opens at the project
    /// root because the branch does not exist yet — `/dev` cuts it at its first write.
    private func confirm() {
        switch activity {
        case .shell: model.tab = .shell; return
        case .agent: model.tab = .agent; return
        case .run:
            if let number = task.taskNumber { model.runs.selectedID = DoorRuns.id(task: number) }
            model.runsOpen = true
            model.dismissSheet()
            return
        case .none: break
        }
        model.startTask(task, agent: defaultConnection)
        model.dismissSheet()
    }
}
