import DeskCore
import SwiftUI

/// The ⓘ in a screen's header (ADR 0046): what the screen holds, what you do there, and what comes before and after,
/// from `Destination.guide`, so every screen explains its place in the flow in the same words and the same spot.
/// `extra` is a screen's own detail under the guide — the Board's column rules.
struct ScreenGuideButton: View {
    let title: String
    let guide: (title: String, lines: [String])
    var extra: String? = nil
    /// The tab's ⓘ ends with the flow line; a small ⓘ inside a tab (Milestones, Run roadmap) does not.
    var showsFlow = true
    var compact = false
    @State private var isShown = false

    init(destination: Destination, extra: String? = nil) {
        self.title = destination.title
        self.guide = destination.guide
        self.extra = extra
    }

    /// A small ⓘ beside one part of a screen (ADR 0046 decision 17).
    init(part title: String, guide: (title: String, lines: [String])) {
        self.title = title
        self.guide = guide
        self.showsFlow = false
        self.compact = true
    }

    var body: some View {
        Button { isShown = true } label: {
            Image(systemName: "info.circle")
                .imageScale(compact ? .small : .medium)
                .foregroundStyle(DeskColor.mutedInk)
                .frame(width: compact ? 18 : DeskMetric.controlHeight, height: compact ? 18 : DeskMetric.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsFlow ? "What \(title) is for, and where it sits in the flow" : "What \(title) does")
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(guide.title)
                    .font(DeskFont.body.weight(.semibold))
                    .foregroundStyle(DeskColor.ink)
                ForEach(guide.lines, id: \.self) { line in
                    Text(line)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsFlow {
                    Text("Findings → Work → Sessions: decide, order, do.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DeskColor.faintInk)
                        .padding(.top, 2)
                }
                if let extra, !extra.isEmpty {
                    Divider()
                    Text(extra)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DeskColor.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 340, alignment: .leading)
            .padding(14)
        }
    }
}
