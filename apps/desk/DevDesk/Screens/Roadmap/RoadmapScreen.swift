import DeskCore
import SwiftUI

struct RoadmapScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Roadmap", message: "")
    }
}
