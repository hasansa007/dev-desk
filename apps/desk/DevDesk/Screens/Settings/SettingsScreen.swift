import DeskCore
import SwiftUI

struct SettingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        EmptyStateView(title: "Settings", message: "")
    }
}
