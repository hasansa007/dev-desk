import AppKit
import DeskCore
import SwiftUI

/// The one chip every filter panel uses (ADR 0046 decisions 15, 18): Findings' Show and Group, Work's filters,
/// Ideation's verdicts, Diagrams' kinds. 28 pt tall, 13 pt text, the count in grey inside, and light blue when on — never
/// black, which was the heaviest thing on screen and appeared nowhere else. A pick-one group keeps exactly one on;
/// a filter group may have none, and the panel shows Clear all while any is.
struct FilterChip: View {
    let label: String
    let isOn: Bool
    var tone: StatusTone? = nil
    var count: String? = nil
    /// A small filled badge before the label — "Now" on the Working now milestone.
    var badge: String? = nil
    /// Long labels (milestone names) are cut to this width; the chip's help carries the full text.
    var maxLabelWidth: CGFloat? = nil
    let action: () -> Void

    init(_ label: String, isOn: Bool, tone: StatusTone? = nil, count: String? = nil, badge: String? = nil,
         maxLabelWidth: CGFloat? = nil, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.tone = tone
        self.count = count
        self.badge = badge
        self.maxLabelWidth = maxLabelWidth
        self.action = action
    }

    init(_ label: String, isOn: Bool, tone: StatusTone? = nil, count: Int, action: @escaping () -> Void) {
        self.init(label, isOn: isOn, tone: tone, count: String(count), action: action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let tone { Circle().fill(DeskColor.tone(tone).dot).frame(width: 7, height: 7) }
                if let badge {
                    Text(badge)
                        // A count badge is the one face the Console prototype leaves non-mono: too small for a mono digit.
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DeskColor.onColorInk)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(DeskColor.accent))
                }
                labelText
                if let count {
                    Text(count)
                        .font(.system(size: 12, design: .monospaced).monospacedDigit())
                        .foregroundStyle(isOn ? DeskColor.accent.opacity(0.75) : DeskColor.faintInk)
                }
            }
        }
        .buttonStyle(ChipButtonStyle(isOn: isOn))
        .fixedSize()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension FilterChip {
    @ViewBuilder var labelText: some View {
        let text = Text(label).font(.system(size: 13, weight: isOn ? .semibold : .regular, design: .monospaced)).lineLimit(1)
        if let maxLabelWidth {
            // Its natural width up to the cap, then cut: `fixedSize` on the chip would otherwise ask for all of it.
            text.truncationMode(.tail).frame(maxWidth: min(maxLabelWidth, Self.width(of: label)), alignment: .leading)
        } else {
            text
        }
    }

    static func width(of label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width) + 1
    }
}

/// The chip's chrome, drawn by a style rather than around a `.plain` button's label: wrapped that way, AppKit's
/// button cell left a sliver of its own bezel at each end of the capsule (seen 2026-09-19 at 2x).
private struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? DeskColor.accent : DeskColor.ink)
            .padding(.horizontal, 12)
            .frame(height: DeskMetric.chipHeight)
            .background {
                // A rounded rectangle at half the height, not a Capsule: the capsule drew 1 px ticks past both ends at
                // 2x whatever stroked it (fill, strokeBorder or an inset stroke), and the Flow menu's rounded box never did.
                let shape = RoundedRectangle(cornerRadius: DeskMetric.chipHeight / 2, style: .continuous)
                shape.fill(isOn ? DeskColor.accent.opacity(0.12) : DeskColor.surface)
                    .overlay(shape.strokeBorder(isOn ? DeskColor.accent.opacity(0.45) : DeskColor.divider, lineWidth: 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.chipHeight / 2, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
