import DeskCore
import SwiftUI

/// The shared chrome for every modal sheet: a headerFill title bar with Cancel/confirm, and a scrolling body.
struct SheetChrome<Content: View>: View {
    let title: String
    let confirmTitle: String
    let cancelTitle: String
    let scrolls: Bool
    let confirmDisabled: Bool
    let cancelHelp: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let content: Content

    /// "Cancel" abandons a pending action. A sheet that is a place rather than an action — the task dialog,
    /// Settings — is left, not cancelled, and says "Close": beside a Stop agent button, "Cancel" reads as if it
    /// would stop the work.
    /// `scrolls: false` for a body that manages its own scrolling — a terminal — because a ScrollView around
    /// one eats the events it needs (ADR 0021 still holds: the dialog's size is fixed either way).
    init(title: String, confirmTitle: String, confirmDisabled: Bool = false, cancelTitle: String = "Cancel",
         scrolls: Bool = true, cancelHelp: String? = nil,
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.confirmDisabled = confirmDisabled
        self.cancelTitle = cancelTitle
        self.scrolls = scrolls
        self.cancelHelp = cancelHelp
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // A terminal scrolls itself, and an enclosing ScrollView takes the wheel and the arrow keys before
            // it ever sees them — which is how a live shell ends up with no scrollback and no ↑/↓.
            if scrolls {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 18)
                }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
            }
        }
        .frame(width: DeskMetric.dialogWidth, height: DeskMetric.dialogHeight)
        .background(DeskColor.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
            Spacer(minLength: 8)
            Button(cancelTitle, action: onCancel)
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .sheetHeader))
                .keyboardShortcut(.cancelAction)
                .help(cancelHelp ?? "")
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .sheetHeader))
                .keyboardShortcut(.defaultAction)
                .disabled(confirmDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}
