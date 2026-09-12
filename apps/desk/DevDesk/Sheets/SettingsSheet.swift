import DeskCore
import SwiftUI

/// Settings is a dialog rather than a destination: you go there to change something and come back to what
/// you were doing, which is not what the sidebar's other entries are for.
struct SettingsSheet: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        SheetChrome(title: "Settings", confirmTitle: "Done",                     onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
            SettingsScreen(model: model)
                .frame(height: 560)
                .background(DeskColor.canvas)
                .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
        }
    }
}
