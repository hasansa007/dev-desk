import DeskCore
import SwiftUI

/// Fades to 35% and back once per `period`; holds still under Reduce Motion.
struct Pulse: ViewModifier {
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, faded in
                view.opacity(faded ? 0.35 : 1)
            } animation: { _ in
                .easeInOut(duration: period / 2)
            }
        }
    }
}

struct StatusDot: View {
    let tone: StatusTone
    var pulses = false
    var size: CGFloat = 7

    var body: some View {
        let dot = Circle()
            .fill(DeskColor.tone(tone).dot)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        if pulses {
            dot.modifier(Pulse(period: 2))
        } else {
            dot
        }
    }
}

struct StatusPill: View {
    let badge: StatusBadge

    var body: some View {
        let colors = DeskColor.tone(badge.tone)
        HStack(spacing: 5) {
            if let symbol = badge.symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            } else if badge.pulses {
                StatusDot(tone: badge.tone, pulses: true, size: 6)
            }
            Text(badge.label)
        }
        .font(.system(size: 11))
        .foregroundStyle(colors.foreground)
        .pill(fill: colors.fill, border: colors.border, horizontalPadding: 7)
        .accessibilityElement(children: .combine)
    }
}

struct PropertyChip: View {
    let text: String
    let tone: StatusTone

    init(_ text: String, tone: StatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        let colors = DeskColor.tone(tone)
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(colors.foreground)
            .pill(fill: tone == .neutral ? DeskColor.neutralChipFill2 : colors.fill, border: colors.border, horizontalPadding: 8)
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DeskFont.label)
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(DeskColor.faintInk)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func deskCard(padding: CGFloat = 11, border: Color = DeskColor.border) -> some View {
        self.padding(padding)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(border))
    }

    fileprivate func pill(fill: Color, border: Color, horizontalPadding: CGFloat) -> some View {
        padding(.vertical, 1)
            .padding(.horizontal, horizontalPadding)
            .background(fill, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(border))
            .fixedSize()
    }
}

struct DeskButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    enum Size { case regular, small, mini }

    let kind: Kind
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        DeskButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct DeskButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DeskButtonStyle.Kind
    let size: DeskButtonStyle.Size
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size == .regular ? 6 : DeskMetric.controlRadius)
        configuration.label
            .font(.system(size: size == .mini ? 11 : 12, weight: kind == .primary ? .semibold : .regular))
            .foregroundStyle(kind == .primary ? Color.white : DeskColor.ink)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(fill, in: shape)
            .overlay {
                if kind == .secondary { shape.strokeBorder(DeskColor.controlBorder) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        let hovered = isHovered && isEnabled
        switch kind {
        case .primary: return hovered ? DeskColor.accentHover : DeskColor.accent
        case .secondary: return hovered ? DeskColor.headerFill : DeskColor.surface
        }
    }

    private var height: CGFloat {
        switch size {
        case .regular: return 28
        case .small: return 26
        case .mini: return 24
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular: return 12
        case .small: return 10
        case .mini: return 8
        }
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DeskColor.accent)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct KeyValueTable: View {
    let rows: [KeyValue]
    var keyWidth: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(DeskColor.rowDivider).frame(height: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(row.key)
                        .foregroundStyle(DeskColor.mutedInk)
                        .frame(width: keyWidth, alignment: .leading)
                    Text(row.value)
                        .font(row.monospaced ? DeskFont.mono(12) : DeskFont.secondary)
                        .foregroundStyle(DeskColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .font(DeskFont.secondary)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }
}

struct NoticeBanner<Actions: View>: View {
    let tone: StatusTone
    let title: String
    let message: String
    let actions: Actions

    init(tone: StatusTone, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        let colors = DeskColor.tone(tone)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(colors.foreground)
                if !message.isEmpty {
                    MarkdownText(message, color: colors.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(12)
        .background(colors.fill, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(colors.border))
    }
}

extension NoticeBanner where Actions == EmptyView {
    init(tone: StatusTone, title: String, message: String) {
        self.init(tone: tone, title: title, message: message) { EmptyView() }
    }
}

struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
            if !message.isEmpty {
                MarkdownText(message, color: DeskColor.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}
