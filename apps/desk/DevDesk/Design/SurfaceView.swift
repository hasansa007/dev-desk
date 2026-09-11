import DeskCore
import SwiftUI

struct SurfaceView<Value, Content: View>: View {
    let surface: Surface<Value>
    let content: (Value) -> Content

    init(_ surface: Surface<Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self.surface = surface
        self.content = content
    }

    var body: some View {
        switch surface {
        case .available(let value): content(value)
        case .unavailable(let reason): UnavailableView(reason: reason)
        }
    }
}

struct UnavailableView: View {
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "eye.slash")
                .foregroundStyle(DeskColor.faintInk)
                .accessibilityHidden(true)
            MarkdownText(reason, color: DeskColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .deskCard(padding: 12)
    }
}
