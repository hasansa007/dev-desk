import DeskCore
import SwiftUI

enum InsightsPlacement { case floating, docked }

struct InsightsPanel: View {
    @Bindable var model: ProjectWindowModel
    let placement: InsightsPlacement

    var body: some View {
        EmptyStateView(title: "Insights", message: "")
    }
}
