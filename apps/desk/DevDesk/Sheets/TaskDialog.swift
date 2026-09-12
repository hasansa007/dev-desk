import DeskCore
import SwiftUI

/// Every card opens this. Selecting a card never leaves the board: the task's issue, its activity, its diff and
/// its evidence all live here, and its terminal lives in the Runs panel rather than behind a second screen.
struct TaskDialog: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    private var isRunning: Bool { model.isTaskRunning(task) }

    var body: some View {
        SheetChrome(title: title, confirmTitle: isRunning ? "View run" : "Start task",
                    confirmDisabled: !isRunning && blockedReason != nil,
                    onCancel: model.dismissSheet, onConfirm: confirm) {
            VStack(alignment: .leading, spacing: 12) {
                facts
                if isRunning {
                    NoticeBanner(tone: .running, title: "This task is running",
                                 message: "Its terminal is in the Runs panel. Ending it there stops the run.", style: .compact) {
                        Button("Open the Runs panel") { model.runsOpen = true }
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
                        Text(tab == .requirements ? "Overview" : tab.title)
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

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .activity: ActivityTab(model: model, task: task)
        case .requirements: RequirementsTab(requirements: task.requirements)
        case .changes: ChangesTab(changes: task.changes)
        case .evidence: EvidenceTab(model: model, evidence: task.evidence)
        }
    }

    /// Why Start task is disabled, or nil when it can run.
    private var blockedReason: String? {
        guard task.taskNumber != nil else { return "This card has no issue number, so `/dev` has nothing to open." }
        return model.runBlockedReason(agent: defaultConnection)
    }

    /// Running: show the run. Not running: start `/dev #N` for it, which opens at the project root because
    /// the branch does not exist yet — `/dev` cuts it at its first write.
    private func confirm() {
        guard let number = task.taskNumber else { return }
        guard !isRunning else {
            model.runs.selectedID = DoorRuns.id(task: number)
            model.runsOpen = true
            model.dismissSheet()
            return
        }
        model.prepareRun(door: "dev", title: "Task #\(number)", agent: defaultConnection,
                         arguments: ["#\(number)"], id: DoorRuns.id(task: number),
                         folderNote: "#\(number) has no branch yet; /dev cuts one at its first write.")
        model.dismissSheet()
    }
}
