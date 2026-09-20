import DeskCore
import SwiftUI

/// A card's dialog is one size (ADR 0021). A confirmation is not a card: it asks one question and is only as
/// big as the question (ADR 0039).
enum SheetSize {
    case card, confirm
}

/// The shared chrome for every modal sheet: a title and a close glyph at the top, the body in the middle, and
/// the actions along the bottom — the shape a Mac dialog has, and the one the task dialog now uses.
///
/// The actions used to sit in the header beside the title, where a window's own controls live, which put
/// "Delete branch" a few pixels from the traffic lights and left a destructive action no place of its own.
struct SheetChrome<Content: View>: View {
    let title: String
    let confirmTitle: String
    let cancelTitle: String
    let scrolls: Bool
    let size: SheetSize
    let confirmDisabled: Bool
    let cancelHelp: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    /// A second, lesser action beside the confirm — Add Task's "Add & start" (ADR 0045). Nil for every other sheet.
    let secondaryTitle: String?
    let onSecondary: (() -> Void)?
    let content: Content

    /// "Cancel" abandons a pending action. A sheet that is a place rather than an action — the task dialog,
    /// Settings — is left, not cancelled, and says "Close": beside a Stop agent button, "Cancel" reads as if it
    /// would stop the work.
    /// `scrolls: false` for a body that manages its own scrolling — a terminal — because a ScrollView around
    /// one eats the events it needs (ADR 0021 still holds: the dialog's size is fixed either way).
    init(title: String, confirmTitle: String, confirmDisabled: Bool = false, cancelTitle: String = "Cancel",
         scrolls: Bool = true, size: SheetSize = .card, cancelHelp: String? = nil,
         secondaryTitle: String? = nil, onSecondary: (() -> Void)? = nil,
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
        self.title = title
        self.confirmTitle = confirmTitle
        self.confirmDisabled = confirmDisabled
        self.cancelTitle = cancelTitle
        self.scrolls = scrolls
        self.size = size
        self.cancelHelp = cancelHelp
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        switch size {
        case .card: card
        case .confirm: confirm
        }
    }

    /// As tall as what it asks, and no wider than a sentence reads well. A body that can grow long — a list —
    /// scrolls inside itself; the chrome never does.
    private var confirm: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .deskSheetWidth(DeskMetric.confirmWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(DeskColor.surface)
    }

    private var card: some View {
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
            footer
        }
        .deskDialogFrame()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeskColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .imageScale(.medium)
                    .foregroundStyle(DeskColor.mutedInk)
                    .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(cancelHelp ?? "Close")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(DeskColor.headerFill)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            Button(cancelTitle, action: onCancel)
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
            if let secondaryTitle, let onSecondary {
                Button(secondaryTitle, action: onSecondary)
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
                    .disabled(confirmDisabled)
            }
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .regular))
                .keyboardShortcut(.defaultAction)
                .disabled(confirmDisabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}
