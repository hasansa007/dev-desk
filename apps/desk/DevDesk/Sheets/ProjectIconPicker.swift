import AppKit
import DeskCore
import UniformTypeIdentifiers
import SwiftUI

/// The menu behind the project icon: an image, one of the identity colours, or back to initials. It is
/// popover CONTENT — the rail owns the anchor, so this view draws no chrome of its own beyond its padding.
///
/// Green and amber are absent by construction: the palette is `ProjectIdentity.palette`, which excludes the
/// running and waiting hues (brief, 2026-09-20).
struct ProjectIconPicker: View {
    let ref: ProjectRef
    let name: String

    @Environment(\.dismiss) private var dismiss
    @State private var store = ProjectIdentityStore.shared
    @State private var failure: String?

    init(ref: ProjectRef, name: String) {
        self.ref = ref
        self.name = name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            label("Project icon")
            Button(action: chooseImage) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose image…").font(DeskFont.secondary).foregroundStyle(DeskColor.ink)
                    Text("PNG or JPG, shown in the strip and here")
                        .font(DeskFont.small).foregroundStyle(DeskColor.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PickerRowStyle())

            if let failure {
                Text(failure)
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.tone(.failed).foreground)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            label("Or a colour")
            HStack(spacing: 6) {
                ForEach(ProjectIdentity.palette, id: \.self) { hex in
                    swatch(hex)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .padding(.top, 4)

            Button {
                store.reset(ref)
                dismiss()
            } label: {
                Text("Reset to initials")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PickerRowStyle())
        }
        .padding(6)
        .frame(width: 260)
        .background(DeskColor.surface)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DeskFont.mono(11))
            .kerning(0.55)
            .foregroundStyle(DeskColor.mutedInk)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func swatch(_ hex: String) -> some View {
        let chosen = store.mark(for: ref) == .color(hex: hex)
        return Button {
            store.setColor(hex, for: ref)
            dismiss()
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(identityHex: hex))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(DeskColor.ink, lineWidth: chosen ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour \(hex)")
    }

    /// The panel is filtered to images, but a file can still be renamed into an extension it is not, so the
    /// store re-checks and the reason lands in the picker rather than in a crash.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.setImage(from: url, for: ref)
            failure = nil
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The prototype's menu row: full-width, no chrome until the pointer is on it.
private struct PickerRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .background(hovering ? DeskColor.neutralChipFill : .clear,
                        in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius - 2))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
