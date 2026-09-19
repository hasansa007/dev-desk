import DeskCore
import SwiftUI

/// The chip every second row uses (ADR 0046 decision 14): Work's filters and Diagrams' kinds look and behave alike.
struct FilterChip: View {
    let label: String
    let isOn: Bool
    var tone: StatusTone? = nil
    let action: () -> Void

    init(_ label: String, isOn: Bool, tone: StatusTone? = nil, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let tone { Circle().fill(DeskColor.tone(tone).dot).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(isOn ? DeskColor.surface : DeskColor.ink)
            .background(Capsule().fill(isOn ? DeskColor.ink : DeskColor.surface))
            .overlay(Capsule().stroke(isOn ? DeskColor.ink : DeskColor.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
