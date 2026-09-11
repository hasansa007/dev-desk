import DeskCore
import SwiftUI

struct ParallelScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Parallel", message: "")
    }
}
