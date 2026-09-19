import DeskCore
import SwiftUI

/// The one chip every second row uses (ADR 0046 decision 15): Findings' Show and Group, Work's filters, Ideation's
/// verdicts, Diagrams' kinds. 28 pt tall, 13 pt text, the count in grey inside, and light blue when on — never
/// black, which was the heaviest thing on screen and appeared nowhere else. A pick-one group keeps exactly one on;
/// a filter group may have none, and shows `ChipClear` while any is.
struct FilterChip: View {
    let label: String
    let isOn: Bool
    var tone: StatusTone? = nil
    var count: String? = nil
    let action: () -> Void

    init(_ label: String, isOn: Bool, tone: StatusTone? = nil, count: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.tone = tone
        self.count = count
        self.action = action
    }

    init(_ label: String, isOn: Bool, tone: StatusTone? = nil, count: Int, action: @escaping () -> Void) {
        self.init(label, isOn: isOn, tone: tone, count: String(count), action: action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let tone { Circle().fill(DeskColor.tone(tone).dot).frame(width: 7, height: 7) }
                Text(label).font(.system(size: 13, weight: isOn ? .semibold : .regular))
                if let count {
                    Text(count)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(isOn ? DeskColor.accent.opacity(0.75) : DeskColor.faintInk)
                }
            }
            .foregroundStyle(isOn ? DeskColor.accent : DeskColor.ink)
            .padding(.horizontal, 12)
            .frame(height: DeskMetric.chipHeight)
            .background(Capsule().fill(isOn ? DeskColor.accent.opacity(0.12) : DeskColor.surface))
            .overlay(Capsule().strokeBorder(isOn ? DeskColor.accent.opacity(0.45) : DeskColor.divider, lineWidth: 1))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The grey word before a chip group: Show, Group, Priority, Type, Verdict, Draw, Flow.
struct ChipGroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(DeskColor.mutedInk).fixedSize()
    }
}

/// The hairline between two chip groups.
struct ChipSeparator: View {
    var body: some View { Rectangle().fill(DeskColor.divider).frame(width: 1, height: 18).padding(.horizontal, 2) }
}

/// A filter group's way back to nothing on.
struct ChipClear: View {
    let action: () -> Void
    var body: some View {
        Button("Clear", action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(DeskColor.accent)
    }
}
