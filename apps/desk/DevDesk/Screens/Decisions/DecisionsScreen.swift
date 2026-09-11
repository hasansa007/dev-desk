import DeskCore
import SwiftUI

struct DecisionsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Decisions", message: "")
    }
}
