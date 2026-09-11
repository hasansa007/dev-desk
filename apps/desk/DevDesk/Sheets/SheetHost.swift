import DeskCore
import SwiftUI

struct SheetHost: View {
    @Bindable var model: ProjectWindowModel
    let kind: SheetKind

    var body: some View {
        switch kind {
        case .openProject:
            LauncherView(context: .sheet, onDismiss: model.dismissSheet)
        case .compareOutputs:
            if let comparison = currentTask?.comparison {
                CompareOutputsSheet(comparison: comparison, onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
            } else {
                SheetChrome(title: "Compare outputs", confirmTitle: "Adopt result", width: 1000, confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() }) {
                    UnavailableView(reason: "No comparison is available for this task.")
                }
            }
        case .followUp:
            if let draft = currentTask?.followUp {
                FollowUpSheet(draft: draft, onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
            } else {
                SheetChrome(title: "Request follow-up", confirmTitle: "Send request", width: 720, confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() }) {
                    UnavailableView(reason: "No follow-up draft is available for this task.")
                }
            }
        case .handoff:
            if let plan = currentTask?.handoff {
                HandoffSheet(plan: plan, onCancel: model.dismissSheet, onConfirm: { model.confirmSheet(provider: $0) })
            } else {
                SheetChrome(title: "Start with handoff", confirmTitle: "Create new session", width: 720, confirmDisabled: true,
                            onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
                    UnavailableView(reason: "No handoff plan is available for this task.")
                }
            }
        case .reconcileFinding(let findingID):
            ReconcileFindingSheet(reconcile: findFinding(findingID)?.reconcile, onCancel: model.dismissSheet, onConfirm: { model.confirmSheet() })
        case .cloneRepository:
            CloneRepositorySheet(onDismiss: model.dismissSheet)
        case .createProject:
            CreateProjectSheet(onDismiss: model.dismissSheet)
        }
    }

    private var currentTask: DeskTask? { model.selectedTask ?? model.lastOpenedTaskID.flatMap(model.task) }

    private func findFinding(_ id: String) -> Finding? {
        model.snapshot?.findings.value?.findings.first { $0.id == id }
    }
}
