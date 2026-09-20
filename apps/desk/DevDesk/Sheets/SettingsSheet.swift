import DeskCore
import SwiftUI

/// Settings is a dialog rather than a destination: you go there to change something and come back to what
/// you were doing, which is not what the sidebar's other entries are for.
///
/// `scrolls: false`: the screen is an index beside one pane, and each side scrolls itself. Wrapped in the
/// chrome's own ScrollView it was a scroll inside a scroll, with the index pinned to a hard-coded 560 pt
/// that neither grew with the dialog nor shrank when the dialog clamped to a small window (2026-09-20).
struct SettingsSheet: View {
    let model: ProjectWindowModel

    var body: some View {
        SheetChrome(title: "Settings", confirmTitle: "Done", cancelTitle: "Close", scrolls: false,
                    onCancel: model.dismissSheet, onConfirm: model.dismissSheet) {
            SettingsChrome { SettingsScreen(model: model) }
        }
    }
}

/// Settings with no project open — Home's ⌘, (ADR 0050). Only the sections that exist without a project are
/// listed; the rest are absent, not inert. Presented by the workspace, which owns the flag that shows it,
/// so closing is the caller's to do.
struct AppSettingsSheet: View {
    let onClose: () -> Void

    var body: some View {
        SheetChrome(title: "Settings", confirmTitle: "Done", cancelTitle: "Close", scrolls: false,
                    onCancel: onClose, onConfirm: onClose) {
            SettingsChrome { SettingsScreen(model: nil) }
        }
    }
}

/// The card the screen sits in, shared so the two entry points cannot drift apart. It sets no size: the
/// dialog is `DeskMetric.dialogWidth` × `dialogHeight` clamped to the window, and that is `SheetChrome`'s.
private struct SettingsChrome<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeskColor.canvas)
            .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }
}
