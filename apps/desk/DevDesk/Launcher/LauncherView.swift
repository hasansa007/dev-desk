import DeskCore
import SwiftUI

enum LauncherContext { case window, sheet }

struct LauncherView: View {
    let context: LauncherContext
    var onDismiss: () -> Void = {}

    var body: some View {
        EmptyStateView(title: "Open Project", message: "")
    }
}
