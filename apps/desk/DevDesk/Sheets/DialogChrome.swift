import DeskCore
import SwiftUI

/// The dialog a card opens: identity at the top, the work in the middle, what you can do to it along the
/// bottom (ADR 0021's fixed size, ADR 0024's one chrome).
///
/// These were `TaskDialog`'s own private views. The survey's findings are cards too and open the same dialog,
/// and a second dialog that merely *looked* like this one would have drifted from it the first time either
/// changed — so the pieces moved here and both dialogs are assembled from them.

/// One action a dialog offers. `blockedReason` both disables the button and says why, next to it, rather than
/// leaving a dead control the developer has to guess at.
struct DialogAction {
    let title: String
    var blockedReason: String?
    var help: String?
    let run: () -> Void
}

/// Title, identity chip, status chips, and the two glyphs a dialog's top-right always has.
struct DialogHeader: View {
    let title: String
    let identifier: String
    var badges: [StatusBadge] = []
    /// Where this thing is actually edited, when that is somewhere else. The app does not edit an issue body,
    /// so the pencil goes to the place that does rather than pretending to be a field.
    var editURL: URL?
    var editHelp = "Edit on GitHub"
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let editURL {
                    DialogGlyph(symbol: "pencil", label: editHelp) { NSWorkspace.shared.open(editURL) }
                }
                DialogGlyph(symbol: "xmark", label: "Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Text(identifier)
                    .font(DeskFont.mono(12))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(DeskColor.border))
                    .textSelection(.enabled)
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    StatusPill(badge: badge, showsDot: false, verticalPadding: 4, horizontalPadding: 10)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(DeskColor.headerFill)
    }
}

struct DialogGlyph: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The underlined tab strip. Tabs are addressed by their title, so a dialog can name its own without every
/// dialog sharing one enum.
struct DialogTabBar: View {
    let titles: [String]
    let selected: String
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles, id: \.self) { title in
                Button { select(title) } label: {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(DeskFont.body)
                            .foregroundStyle(selected == title ? DeskColor.ink : DeskColor.mutedInk)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        Rectangle()
                            .fill(selected == title ? DeskColor.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == title ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

/// The scrolling middle: anything the dialog wants above the body, then the body on its own surface.
struct DialogBody<Meta: View, Content: View>: View {
    @ViewBuilder var meta: () -> Meta
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                meta()
                content()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                    .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
        }
    }
}

/// Actions live along the bottom. They were in the header beside the title, which put "Start task" and
/// "Close" where a window's own controls sit, and left the destructive action nowhere.
struct DialogFooter<Leading: View>: View {
    let primary: DialogAction
    /// Sits beside the primary — a second thing you can do that is not destructive and not Close.
    var secondary: DialogAction?
    let close: () -> Void
    @ViewBuilder var leading: () -> Leading

    init(primary: DialogAction, secondary: DialogAction? = nil, close: @escaping () -> Void,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }) {
        self.primary = primary
        self.secondary = secondary
        self.close = close
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Spacer(minLength: 8)
            if let blocked = primary.blockedReason {
                Text(blocked)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
            }
            if let secondary {
                Button(secondary.title) { secondary.run() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
                    .disabled(secondary.blockedReason != nil)
                    .help(secondary.help ?? "")
            }
            Button(primary.title) { primary.run() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .regular))
                .disabled(primary.blockedReason != nil)
                .help(primary.help ?? "")
                .keyboardShortcut(.defaultAction)
            Button("Close", action: close)
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

extension View {
    /// Every card's dialog is the same size, whatever opened it (ADR 0021).
    func deskDialogFrame() -> some View {
        frame(width: DeskMetric.dialogWidth, height: DeskMetric.dialogHeight)
            .background(DeskColor.surface)
    }
}
