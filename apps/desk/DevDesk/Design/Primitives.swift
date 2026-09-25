import DeskCore
import SwiftUI

/// Fades to 35% and back once per `period`, driven by the clock so a dot that moves never animates its position; still under Reduce Motion.
struct Pulse: ViewModifier {
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                content.opacity(1 - 0.325 * (1 - cos(2 * .pi * phase)))
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

/// Board cards show the pulsing dot; the task header and parallel panes show the label alone (D:191, D:248, D:286).
struct StatusPill: View {
    let badge: StatusBadge
    var showsDot = true
    var verticalPadding: CGFloat = 1
    var horizontalPadding: CGFloat = 7

    var body: some View {
        let colors = DeskColor.tone(badge.tone)
        HStack(spacing: 5) {
            if let symbol = badge.symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            } else if badge.pulses && showsDot {
                StatusDot(tone: badge.tone, pulses: true, size: 6)
            }
            Text(badge.label)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(colors.foreground)
        .pill(fill: colors.fill, border: colors.border, vertical: verticalPadding, horizontal: horizontalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// A neutral chip takes the badge fill (D:426); filter and roadmap chips pass `DeskColor.neutralChipFill2` (D:536, D:605).
struct PropertyChip: View {
    let text: String
    let tone: StatusTone
    let fill: Color?
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat

    init(_ text: String, tone: StatusTone = .neutral, fill: Color? = nil, verticalPadding: CGFloat = 1, horizontalPadding: CGFloat = 8) {
        self.text = text
        self.tone = tone
        self.fill = fill
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        let colors = DeskColor.tone(tone)
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(colors.foreground)
            .pill(fill: fill ?? colors.fill, border: colors.border, vertical: verticalPadding, horizontal: horizontalPadding)
    }
}

extension View {
    /// The bar a screen's title sits in: one surface, one rule under it, and it never scrolls away with the work.
    /// Every screen's header sits on the content layer, not the object layer (ADR 0046, three layers): navigation
    /// is `sidebar`, content is `canvas`, the things you act on are `surface`.
    func screenHeaderBar() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DeskColor.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

/// The ⌘ key that reaches a place, as a keycap at its icon's bottom-left (#96) — the corner no count or dot uses.
struct KeyHint: View {
    let key: String

    var body: some View {
        Text(verbatim: "⌘" + key.uppercased())
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(DeskColor.mutedInk)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .background(DeskColor.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DeskColor.controlBorder, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
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
    /// Every card in the app: one fill, one radius, one border, and selection drawn the same way wherever a
    /// card can be selected. A card that draws its own chrome drifts from this one the first time either moves.
    func deskCard(padding: CGFloat = 11, border: Color = DeskColor.border, isSelected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        return self.padding(padding)
            .background(DeskColor.surface, in: shape)
            .overlay(shape.strokeBorder(isSelected ? DeskColor.accent : border))
            .overlay { if isSelected { shape.inset(by: -1.5).stroke(DeskColor.accent.opacity(0.14), lineWidth: 3) } }
            .contentShape(shape)
    }

    /// One height, radius and border for the controls that are not buttons, so a header never mixes a capsule with a rounded rectangle.
    func controlChrome(fill: Color = DeskColor.surface, border: Color = DeskColor.controlBorder,
                       height: CGFloat = DeskMetric.controlHeight) -> some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        return frame(height: height)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border))
    }

    fileprivate func pill(fill: Color, border: Color, vertical: CGFloat, horizontal: CGFloat) -> some View {
        padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .background(fill, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(border))
            .fixedSize()
    }
}

struct DeskButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    /// The design's button geometries: height, corner radius, horizontal padding and label size.
    struct Size {
        let height: CGFloat
        let radius: CGFloat
        let padding: CGFloat
        let fontSize: CGFloat

        static let regular = Size(height: 28, radius: 6, padding: 12, fontSize: 12)
        static let small = Size(height: 26, radius: 6, padding: 10, fontSize: 12)
        static let smallWide = Size(height: 26, radius: 6, padding: 11, fontSize: 12)
        static let mini = Size(height: 24, radius: 5, padding: 9, fontSize: 11)
        static let sheetHeader = Size(height: 27, radius: 6, padding: 12, fontSize: 12)
        static let decision = Size(height: 29, radius: 6, padding: 12, fontSize: 12)
        static let decisionPrimary = Size(height: 29, radius: 6, padding: 14, fontSize: 12)
        static let composer = Size(height: 30, radius: 7, padding: 12, fontSize: 12)
    }

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
        let shape = RoundedRectangle(cornerRadius: size.radius)
        configuration.label
            .font(.system(size: size.fontSize, weight: kind == .primary ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(kind == .primary ? DeskColor.onColorInk : DeskColor.ink)
            .lineLimit(1)
            .padding(.horizontal, size.padding)
            .frame(height: size.height)
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

/// Where a banner's actions sit, with its padding and radius, per the design's variants (D:332, D:266, D:434, D:732).
struct NoticeStyle {
    let stacksActions: Bool
    let padding: CGFloat
    let radius: CGFloat
    let titleGap: CGFloat
    let actionsGap: CGFloat

    static let inline = NoticeStyle(stacksActions: false, padding: 14, radius: 9, titleGap: 6, actionsGap: 14)
    static let stacked = NoticeStyle(stacksActions: true, padding: 12, radius: 9, titleGap: 6, actionsGap: 10)
    static let compact = NoticeStyle(stacksActions: true, padding: 11, radius: 8, titleGap: 5, actionsGap: 10)
    static let callout = NoticeStyle(stacksActions: true, padding: 12, radius: 8, titleGap: 5, actionsGap: 9)
}

/// An empty title renders the message alone, as the design's single-paragraph notes do (D:673, D:690).
struct NoticeBanner<Actions: View>: View {
    let tone: StatusTone
    let title: String
    let message: String
    let style: NoticeStyle
    let actions: Actions

    init(tone: StatusTone, title: String, message: String, style: NoticeStyle = .inline, @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.title = title
        self.message = message
        self.style = style
        self.actions = actions()
    }

    var body: some View {
        let colors = DeskColor.tone(tone)
        let shape = RoundedRectangle(cornerRadius: style.radius)
        content
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.fill, in: shape)
            .overlay(shape.strokeBorder(colors.border))
    }

    @ViewBuilder private var content: some View {
        if style.stacksActions {
            VStack(alignment: .leading, spacing: 0) {
                text
                if Actions.self != EmptyView.self {
                    actions.padding(.top, style.actionsGap)
                }
            }
        } else {
            HStack(alignment: .top, spacing: style.actionsGap) {
                text.frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
        }
    }

    private var text: some View {
        let colors = DeskColor.tone(tone)
        return VStack(alignment: .leading, spacing: style.titleGap) {
            if !title.isEmpty {
                Text(title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(colors.foreground)
            }
            if !message.isEmpty {
                MarkdownText(message, color: colors.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension NoticeBanner where Actions == EmptyView {
    init(tone: StatusTone, title: String, message: String, style: NoticeStyle = .inline) {
        self.init(tone: tone, title: title, message: message, style: style) { EmptyView() }
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
