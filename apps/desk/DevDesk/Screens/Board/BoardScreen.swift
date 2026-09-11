import DeskCore
import SwiftUI

struct BoardScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Board", message: "")
    }
}
