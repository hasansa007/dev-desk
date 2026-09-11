import DeskCore
import SwiftUI

struct TaskWorkspaceScreen: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let showsInspector = width >= 980
            let sideFits = width >= 1200
            let sideDockFallsBack = model.dockPlacement == .side && !sideFits
            VStack(spacing: 0) {
                TaskHeader(model: model, task: task, showsAgentsButton: !showsInspector, sideDockFallsBack: sideDockFallsBack)
                workspace(showsInspector: showsInspector,
                          placement: sideFits ? model.dockPlacement : .bottom,
                          sideDockFallsBack: sideDockFallsBack)
            }
            .id(task.id)
        }
    }

    private func workspace(showsInspector: Bool, placement: DockPlacement, sideDockFallsBack: Bool) -> some View {
        let layout = placement == .side ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            HStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if showsInspector {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(DeskColor.divider)
                            .frame(width: 1)
                        ScrollView {
                            AgentsInspector(model: model, task: task, sideDockFallsBack: sideDockFallsBack)
                        }
                    }
                    .frame(width: DeskMetric.inspectorWidth)
                    .background(DeskColor.inspector)
                }
            }
            if model.dockOpen, let dock = task.dock {
                AgentsDock(model: model, task: task, dock: dock, placement: placement)
                    .frame(width: placement == .side ? DeskMetric.dockSideWidth : nil,
                           height: placement == .bottom ? DeskMetric.dockHeight : nil)
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case .activity:
            scrolling { ActivityTab(model: model, task: task) }
        case .requirements:
            scrolling { RequirementsTab(requirements: task.requirements) }
        case .changes:
            ChangesTab(changes: task.changes)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
        case .evidence:
            scrolling { EvidenceTab(model: model, evidence: task.evidence) }
        }
    }

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TaskWorkspaceScreen_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(["42", "57", "63"], id: \.self) { taskID in
            TaskWorkspacePreview(taskID: taskID)
                .frame(width: 1204, height: 860)
                .previewDisplayName("Task #\(taskID)")
        }
    }
}

private struct TaskWorkspacePreview: View {
    let taskID: String
    @State private var model: ProjectWindowModel

    init(taskID: String) {
        self.taskID = taskID
        _model = State(initialValue: ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub)))
    }

    var body: some View {
        Group {
            if let task = model.selectedTask, task.id == taskID {
                TaskWorkspaceScreen(model: model, task: task)
            } else {
                ProgressView()
            }
        }
        .background(DeskColor.canvas)
        .task {
            await model.load()
            model.openTask(taskID)
        }
    }
}
