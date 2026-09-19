import DeskCore
import SwiftUI

/// The ⓘ in a screen's header (ADR 0046): what the screen holds, what you do there, and what comes before and after,
/// from `Destination.guide`, so every screen explains its place in the flow in the same words and the same spot.
/// `extra` is a screen's own detail under the guide — the Board's column rules.
struct ScreenGuideButton: View {
    let destination: Destination
    var extra: String? = nil
    @State private var isShown = false

    var body: some View {
        Button { isShown = true } label: {
            Image(systemName: "info.circle")
                .imageScale(.medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: DeskMetric.controlHeight, height: DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What \(destination.title) is for, and where it sits in the flow")
        .accessibilityLabel("About \(destination.title)")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(destination.guide.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                ForEach(destination.guide.lines, id: \.self) { line in
                    Text(line)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Findings → Work → Sessions: decide, order, do.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .padding(.top, 2)
                if let extra, !extra.isEmpty {
                    Divider()
                    Text(extra)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 340, alignment: .leading)
            .padding(14)
        }
    }
}
