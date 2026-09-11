import DeskCore
import SwiftUI

/// The shared chrome for every modal sheet: a headerFill title bar with Cancel/confirm, and a scrolling body.
struct SheetChrome<Content: View>: View {
    let title: String
    let confirmTitle: String
    let width: CGFloat
    var confirmDisabled = false
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let content: Content

    init(title: String, confirmTitle: String, width: CGFloat, confirmDisabled: Bool = false,
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.width = width
        self.confirmDisabled = confirmDisabled
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
            }
        }
        .frame(width: width)
        .frame(maxHeight: 790)
        .background(DeskColor.surface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
            Spacer(minLength: 8)
            SheetHeaderButton(title: "Cancel", kind: .secondary, action: onCancel)
            SheetHeaderButton(title: confirmTitle, kind: .primary, action: onConfirm, disabled: confirmDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

/// The sheet header's own button size (27pt) sits between the primitive's `.small` (26) and `.regular` (28).
private struct SheetHeaderButton: View {
    enum Kind { case primary, secondary }
    let title: String
    let kind: Kind
    let action: () -> Void
    var disabled = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(kind == .primary ? Color.white : DeskColor.ink)
                .padding(.horizontal, 12)
                .frame(height: 27)
        }
        .buttonStyle(.plain)
        .background(kind == .primary ? DeskColor.accent : DeskColor.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(kind == .primary ? DeskColor.accent : DeskColor.controlBorder))
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}
