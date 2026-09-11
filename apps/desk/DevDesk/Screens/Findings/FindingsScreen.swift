import DeskCore
import SwiftUI

struct FindingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Findings", message: "")
    }
}
