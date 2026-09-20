import DeskCore
import SwiftUI

// The one visual system Settings is allowed. Before this file there were five near-identical row shapes —
// a 200-wide right-aligned label, a bare Toggle, a bare Stepper, a hand-rolled TextField chrome copied three
// times, and a loose Text() caption at 8, 10 or 12 points of top padding depending on which pane wrote it —
// so no two panes lined up and changing the look of "a setting" meant finding all five (2026-09-20).

/// Whose setting this is. A pane that does not say it invites the question on every visit — and the
/// Project overrides pane answered it wrongly, with a caption denying the two Dev Desk preferences under it.
enum SettingScope {
    case everyProject, thisProject

    var label: String {
        switch self {
        case .everyProject: return "all projects"
        case .thisProject: return "this project"
        }
    }
}

/// A pane's heading: what it is, whose it is, and one line of what is under it — at one geometry, because
/// six panes previously opened six different ways and only some of them said what the pane was for.
struct PaneHeader: View {
    let title: String
    let scope: SettingScope
    let summary: String

    init(_ title: String, scope: SettingScope, summary: String) {
        self.title = title
        self.scope = scope
        self.summary = summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(DeskFont.section)
                    .foregroundStyle(DeskColor.ink)
                    .accessibilityAddTraits(.isHeader)
                PropertyChip(scope.label)
                Spacer(minLength: 0)
            }
            MarkdownText(summary, font: DeskFont.secondary, color: DeskColor.mutedInk)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A group of settings, on the object layer, with one hairline between rows. The VStack is pulled up a point
/// and clipped so every row can draw its own top rule and the first one lands under the card's edge — cheaper
/// than every call site knowing whether it is first.
struct SettingCard<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(title) }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
                .clipShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
            // An empty footer is no footer: two call sites build theirs from a snapshot that may say nothing.
            if let footer, !footer.isEmpty { SettingNote(footer) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The padding and the hairline every row in a card shares, whatever the row holds.
struct SettingRowShell<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(DeskColor.rowDivider).frame(height: 1)
            content
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One setting: its name, its control on the right, and the line underneath saying what changing it does.
/// `why` is not optional in this app's voice — a toggle with a bare label is a setting you learn by trying it,
/// and "Auto" spends tokens unattended when you try it.
///
/// `unavailable` is the reason there is nothing to change here — a sample with no folder, a CLI that is not
/// installed. It disables the control and prints the reason, because a control that is silently inert is a
/// control that lies.
struct SettingRow<Control: View>: View {
    let title: String
    let why: String
    let unavailable: String?
    let control: Control

    init(_ title: String, why: String, unavailable: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.why = why
        self.unavailable = unavailable
        self.control = control()
    }

    var body: some View {
        SettingRowShell {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 14) {
                    Text(title)
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    control
                        .disabled(unavailable != nil)
                        .opacity(unavailable == nil ? 1 : 0.45)
                }
                SettingWhy(why: why, unavailable: unavailable)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// A row whose control needs the whole width — a list of commands, a picker with a preview beside it. Same
/// hairline, same padding, same why line; only the control is allowed to be big.
struct SettingBlockRow<Control: View>: View {
    let title: String
    let why: String
    let unavailable: String?
    let control: Control

    init(_ title: String, why: String, unavailable: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.why = why
        self.unavailable = unavailable
        self.control = control()
    }

    var body: some View {
        SettingRowShell {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.ink)
                SettingWhy(why: why, unavailable: unavailable)
                control
                    .disabled(unavailable != nil)
                    .opacity(unavailable == nil ? 1 : 0.45)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Why the setting exists, then — when it cannot be used — why it cannot. Both, never one instead of the
/// other: knowing a folder is missing does not tell you what the folder would have been for.
private struct SettingWhy: View {
    let why: String
    let unavailable: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !why.isEmpty {
                MarkdownText(why, font: DeskFont.secondary, color: DeskColor.mutedInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let unavailable { UnavailableLine(unavailable) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one way Settings says "there is nothing to change here, and here is why". Grey with a barred glyph,
/// never red and never amber: unavailable is not a failure, and the two status colours are spoken for.
struct UnavailableLine: View {
    let reason: String

    init(_ reason: String) { self.reason = reason }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "slash.circle")
                .font(DeskFont.mono(10))
                .foregroundStyle(DeskColor.faintInk)
                .padding(.top, 2)
                .accessibilityHidden(true)
            MarkdownText(reason, font: DeskFont.secondary, color: DeskColor.secondaryInk)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unavailable: \(reason)")
    }
}

/// A paragraph that belongs to a card rather than to a row — the footnote under a table, mostly.
struct SettingNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        MarkdownText(text, font: DeskFont.secondary, color: DeskColor.mutedInk)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The controls themselves

/// A switch, right-aligned in the control column like every other control, so a card of mixed rows still has
/// one edge. `.checkbox` and `.switch` were both in use, a column apart.
struct SettingToggle: View {
    let title: String
    let why: String
    var unavailable: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title, why: why, unavailable: unavailable) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}

/// A number with its own words beside the stepper — "3 agents", not a bare 3 — because the unit is the
/// setting and a stepper's own label is on the wrong side of the row.
struct SettingStepper<Value: Strideable>: View where Value.Stride: SignedNumeric {
    let title: String
    let why: String
    let valueLabel: String
    let range: ClosedRange<Value>
    var step: Value.Stride = 1
    var unavailable: String? = nil
    @Binding var value: Value

    var body: some View {
        SettingRow(title, why: why, unavailable: unavailable) {
            HStack(spacing: 8) {
                Text(valueLabel)
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.ink)
                    .monospacedDigit()
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue(valueLabel)
            }
        }
    }
}

extension View {
    /// The one text field chrome in Settings. Recessed (`canvas`) against a card's raised `surface`, so a
    /// field is a hole in the card in both appearances rather than a border drawn on nothing.
    func settingField(width: CGFloat? = nil, isInvalid: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
        return textFieldStyle(.plain)
            .font(DeskFont.mono(12))
            .foregroundStyle(DeskColor.ink)
            .padding(.horizontal, 10)
            .frame(width: width, height: 28)
            .background(DeskColor.canvas, in: shape)
            .overlay(shape.strokeBorder(isInvalid ? DeskColor.tone(.failed).dot : DeskColor.controlBorder))
    }

    /// A menu or segmented picker at the width the control column allows, with its own label off: every
    /// picker in Settings is labelled by its row and would otherwise be labelled twice.
    func settingPicker(width: CGFloat) -> some View {
        labelsHidden().frame(width: width)
    }
}
