import SwiftUI

/// The grab strip between the work and a panel edge. A panel whose size is a constant is a decision made once
/// for every project and every screen; this hands it back, and keeps it inside bounds that stay usable.
struct EdgeResizer: View {
    enum Edge { case bottom, trailing }

    let edge: Edge
    @Binding var size: Double
    let range: ClosedRange<Double>
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(DeskColor.border)
            .frame(width: edge == .trailing ? 1 : nil, height: edge == .bottom ? 1 : nil)
            .overlay {
                // The line is a hairline; the target is not. Six points either side is what a divider needs
                // before it can be caught with a mouse.
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: edge == .trailing ? 9 : nil, height: edge == .bottom ? 9 : nil)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let from = start ?? size
                                if start == nil { start = size }
                                // Both edges grow toward the window's centre, so both read their drag inverted.
                                let delta = edge == .bottom ? -value.translation.height : -value.translation.width
                                size = min(max(from + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .accessibilityLabel(edge == .bottom ? "Resize the Runs panel" : "Resize the Files panel")
    }
}
