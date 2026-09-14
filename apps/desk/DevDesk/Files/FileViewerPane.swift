import AppKit
import DeskCore
import SwiftUI

/// How the viewer shows a text file: the bytes as they are written, or markdown rendered.
enum FileViewMode: String, CaseIterable { case code, preview }

/// The selected file, as a pane of its own with a nav bar of its own. Where it sits is `ContentRouter`'s
/// decision — a column beside the work, or floating over it — so this only ever draws one file.
struct FileViewerPane: View {
    let model: ProjectWindowModel
    /// The path relative to the project root, as the tree spells it.
    let path: String
    /// The absolute URL that path names, or nil when it does not name one inside the project.
    let url: URL?
    let root: URL
    @Binding var isExpanded: Bool
    @State private var mode: FileViewMode = .code

    /// Reading rules stay `FileReader`'s: a symlink, an oversize file and a binary one each say so instead of being shown.
    private var preview: FilePreview {
        guard let url else { return .unreadable("This file resolves outside the project, so it is not read.") }
        return FileReader.read(url, within: root)
    }

    private var isMarkdown: Bool {
        ["md", "markdown"].contains((url?.pathExtension ?? "").lowercased())
    }

    var body: some View {
        let file = preview
        VStack(spacing: 0) {
            navBar(file)
            contents(of: file)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.surface)
    }

    @ViewBuilder private func contents(of preview: FilePreview) -> some View {
        Group {
            if case .text(let contents) = preview {
                if mode == .preview, isMarkdown {
                    ScrollView {
                        MarkdownText(contents, font: DeskFont.body)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(contents.isEmpty ? "This file is empty." : contents)
                            .font(DeskFont.mono(11.5))
                            .foregroundStyle(contents.isEmpty ? DeskColor.mutedInk : DeskColor.ink)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                UnavailableView(reason: preview.message ?? "")
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The app's header, one row: what the file is, then what can be done to it.
    private func navBar(_ preview: FilePreview) -> some View {
        HStack(spacing: 6) {
            Text(path)
                .font(DeskFont.mono(11))
                .foregroundStyle(DeskColor.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 6)
            // Nothing to render and nothing to read: a binary or oversize file gets no choice of how to show it.
            if case .text = preview { modeToggle }
            if let url {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Reveal in Finder")
            }
            Button("Open") { model.openSelectedFile() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                .help("Open in the default editor")
            glyph(isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                  help: isExpanded ? "Back to the split view" : "Fill the window") { isExpanded.toggle() }
            glyph("xmark", help: "Close this file") { model.closeFile() }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(DeskColor.headerFill)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// Rendered or raw. A file that is not markdown has nothing to render, so Preview shows it the same way.
    private var modeToggle: some View {
        HStack(spacing: 4) {
            Button("Preview") { mode = .preview }
                .buttonStyle(DeskButtonStyle(kind: mode == .preview ? .primary : .secondary, size: .mini))
                .help(isMarkdown ? "Render this markdown" : "This file is not markdown, so Preview shows the same text")
            Button("</>") { mode = .code }
                .buttonStyle(DeskButtonStyle(kind: mode == .code ? .primary : .secondary, size: .mini))
                .help("Show the file as it is written")
        }
    }

    private func glyph(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).imageScale(.small) }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
            .help(help)
            .accessibilityLabel(help)
    }
}

/// Handing a file to whatever the system opens it with. `NSWorkspace` is AppKit's, so it stays in the app
/// target and the model is given the call; the old `open(_:)` returned a Bool nobody read, which is why a
/// refusal looked like nothing happening at all.
enum FileOpen {
    /// nil when the file opened; the system's own reason when it did not.
    static func inEditor(_ url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }
}
