import DeskCore
import SwiftUI

struct SheetHost: View {
    @Bindable var model: ProjectWindowModel
    let kind: SheetKind

    var body: some View {
        sheet.modifier(DeskLinkRouting(model: model))
    }

    @ViewBuilder private var sheet: some View {
        switch kind {
        case .openProject:
            LauncherView(context: .sheet, onDismiss: model.dismissSheet)
        case .compareOutputs:
            if let comparison = currentTask?.comparison {
                CompareOutputsSheet(title: taskTitled("Compare agent outputs"), comparison: comparison,
                                    onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
            } else {
                SheetChrome(title: taskTitled("Compare agent outputs"), confirmTitle: "Adopt result", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() }) {
                    UnavailableView(reason: "No comparison is available for this task.")
                }
            }
        case .followUp:
            if let draft = currentTask?.followUp {
                FollowUpSheet(draft: draft, onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
            } else {
                SheetChrome(title: "Request follow-up", confirmTitle: "Send request", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() }) {
                    UnavailableView(reason: "No follow-up draft is available for this task.")
                }
            }
        case .handoff:
            if let plan = currentTask?.handoff {
                HandoffSheet(title: taskTitled("Start with handoff"), plan: plan,
                             onCancel: model.dismissSheet, onConfirm: { model.confirmSheet(provider: $0) })
            } else {
                SheetChrome(title: taskTitled("Start with handoff"), confirmTitle: "Create new session", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
                    UnavailableView(reason: "No handoff plan is available for this task.")
                }
            }
        case .reconcileFinding(let findingID):
            ReconcileFindingSheet(title: reconcileTitle(findingID), reconcile: findFinding(findingID)?.reconcile,
                                  onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
        case .task(let taskID):
            if let task = model.task(taskID) {
                TaskDialog(model: model, task: task)
            } else {
                SheetChrome(title: "Task", confirmTitle: "Start task", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
                    UnavailableView(reason: "This task is no longer on the board.")
                }
            }
        case .finding(let findingID):
            if let finding = findFinding(findingID) {
                FindingDialog(finding: finding, model: model)
            } else {
                SheetChrome(title: "Finding", confirmTitle: "Add to backlog…", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
                    UnavailableView(reason: "This finding is not in the survey report any more.")
                }
            }
        case .cancelTask(let taskID):
            if let task = model.task(taskID) {
                CancelTaskSheet(model: model, task: task)
            } else {
                SheetChrome(title: "Close as not planned", confirmTitle: "Close", confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
                    UnavailableView(reason: "This task is no longer on the board.")
                }
            }
        case .runFocus(let door):
            RunFocusSheet(model: model, door: door)
        case .deleteBranch(let branch):
            DeleteBranchSheet(model: model, branch: branch)
        case .settings:
            SettingsSheet(model: model)
        case .cloneRepository:
            CloneRepositorySheet(onDismiss: model.dismissSheet)
        case .createProject:
            CreateProjectSheet(onDismiss: model.dismissSheet)
        case .resetSurvey:
            ResetSurveySheet(model: model)
        }
    }

    private var currentTask: DeskTask? { model.selectedTask ?? model.lastOpenedTaskID.flatMap(model.task) }

    private func taskTitled(_ title: String) -> String {
        guard let label = currentTask?.issueLabel, !label.isEmpty else { return title }
        return "\(title) · \(label)"
    }

    private func reconcileTitle(_ findingID: String) -> String {
        guard let issue = findFinding(findingID)?.reconcile?.candidateIssue else { return "Reconcile with the tracker" }
        return "Compare finding \(findingID) with issue #\(issue)"
    }

    private func findFinding(_ id: String) -> Finding? {
        model.snapshot?.findings.value?.findings.first { $0.id == id }
    }
}
