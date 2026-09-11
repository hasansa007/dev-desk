import DeskCore
import SwiftUI

struct TaskWorkspaceScreen: View {
    @Bindable var model: ProjectWindowModel
    let task: DeskTask

    var body: some View {
        EmptyStateView(title: "Task", message: "")
    }
}
