import DeskCore
import SwiftUI

struct SurfaceView<Value, Content: View>: View {
    let surface: Surface<Value>
    let fillsScreen: Bool
    let content: (Value) -> Content

    /// `fillsScreen` pins an unavailable reason to the top of a whole screen instead of centring it.
    init(_ surface: Surface<Value>, fillsScreen: Bool = false, @ViewBuilder content: @escaping (Value) -> Content) {
        self.surface = surface
        self.fillsScreen = fillsScreen
        self.content = content
    }

    var body: some View {
        switch surface {
        case .available(let value):
            content(value)
        case .unavailable(let reason):
            if fillsScreen {
                UnavailableView(reason: reason)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                UnavailableView(reason: reason)
            }
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
