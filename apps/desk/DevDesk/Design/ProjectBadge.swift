import AppKit
import DeskCore
import SwiftUI

/// A project's mark, and nothing else: the strip draws its own selection bar and its own run counts on top,
/// because the same badge also sits in the rail header where neither belongs.
///
/// The prototype's `.pj`: a squircle that rounds further on hover (10 → 14 at 36pt), initials in mono.
struct ProjectBadge: View {
    let ref: ProjectRef
    let name: String
    var size: CGFloat = 36

    @State private var hovering = false

    init(ref: ProjectRef, name: String, size: CGFloat = 36) {
        self.ref = ref
        self.name = name
        self.size = size
    }

    private var identity: ProjectIdentity { ProjectIdentityStore.shared.identity(for: ref, name: name) }
    private var radius: CGFloat { (hovering ? 0.39 : 0.28) * size }

    var body: some View {
        let identity = identity
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let path = identity.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(identityHex: identity.colorHex)
                Text(identity.initials)
                    // Ink is picked against the mark's own luminance: a pale identity with pale initials on it
                    // is unreadable at 36pt.
                    .foregroundStyle(Color.identityInk(onHex: identity.colorHex))
                    .font(DeskFont.mono(size * 0.32, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel(name)
    }
}

extension Color {
    /// The identity palette is this slice's own data, so it arrives as hex rather than as a token; it is the
    /// one place in the app that does (brief, 2026-09-20).
    init(identityHex hex: String) {
        let rgb = ProjectIdentity.rgbComponents(ofHex: hex) ?? (0.61, 0.75, 1.0)
        self = Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: 1)
    }

    static func identityInk(onHex hex: String) -> Color {
        let rgb = ProjectIdentity.rgbComponents(ofHex: hex) ?? (0.61, 0.75, 1.0)
        let luminance = 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
        return luminance > 0.55 ? Color(.sRGB, white: 0.06, opacity: 1) : DeskColor.ink
    }
}
