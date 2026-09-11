import AppKit
import DeskCore
import SwiftUI

/// The project's own folder, listed one directory at a time. Nothing is walked up front, so a repository
/// carrying node_modules opens as fast as an empty one.
struct FilesScreen: View {
    @Bindable var model: ProjectWindowModel
    @State private var expanded: Set<String> = []
    @State private var children: [String: [FileEntry]] = [:]

    private var root: URL? {
        if case .local(let path) = model.ref { return URL(fileURLWithPath: path, isDirectory: true) }
        return nil
    }

    var body: some View {
        if let root {
            HStack(spacing: 0) {
                treePane(root)
                viewerPane(root)
            }
            .task(id: model.ref.id) { loadRoot(root) }
        } else {
            UnavailableView(reason: "Sample projects have no folder on disk, so there is nothing to browse.")
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func treePane(_ root: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Files").font(DeskFont.section)
                Spacer(minLength: 0)
                Text(root.lastPathComponent)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows(root), id: \.entry.id) { row in
                        FileRow(entry: row.entry, depth: row.depth,
                                isExpanded: expanded.contains(row.entry.id),
                                isSelected: row.entry.id == model.selectedFilePath) {
                            select(row.entry, root: root)
                        }
                    }
                }
            }
        }
        .frame(width: 320, alignment: .leading)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    @ViewBuilder private func viewerPane(_ root: URL) -> some View {
        if let path = model.selectedFilePath {
            FileViewer(url: root.appendingPathComponent(path), path: path, root: root)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyStateView(title: "No file selected", message: "Pick a file on the left to read it here.")
        }
    }

    /// The visible rows: the root's entries, with an expanded directory's children spliced in beneath it.
    private func rows(_ root: URL) -> [(entry: FileEntry, depth: Int)] {
        var result: [(FileEntry, Int)] = []
        func append(_ entries: [FileEntry], depth: Int) {
            for entry in entries {
                result.append((entry, depth))
                if entry.isExpandable, expanded.contains(entry.id), let nested = children[entry.id] {
                    append(nested, depth: depth + 1)
                }
            }
        }
        append(children[""] ?? [], depth: 0)
        return result.map { (entry: $0.0, depth: $0.1) }
    }

    private func loadRoot(_ root: URL) {
        guard children[""] == nil else { return }
        children[""] = FileTree.list(root, within: root)
    }

    /// A directory toggles, reading its children the first time; a file becomes the selection.
    private func select(_ entry: FileEntry, root: URL) {
        guard entry.isExpandable else {
            model.selectedFilePath = entry.id
            return
        }
        if expanded.contains(entry.id) {
            expanded.remove(entry.id)
        } else {
            if children[entry.id] == nil {
                children[entry.id] = FileTree.list(root.appendingPathComponent(entry.id), within: root)
            }
            expanded.insert(entry.id)
        }
    }
}

private struct FileRow: View {
    let entry: FileEntry
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(entry.isDirectory ? DeskColor.accent : DeskColor.faintInk)
                    .frame(width: 14)
                Text(entry.name)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let size = entry.size {
                    Text(FileRow.readableSize(size))
                        .font(DeskFont.mono(10.5))
                        .foregroundStyle(DeskColor.faintInk)
                }
            }
            .padding(.vertical, 5)
            .padding(.trailing, 12)
            .padding(.leading, CGFloat(12 + depth * 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
        }
        .buttonStyle(.plain)
        .help(entry.isSymlink ? "A symbolic link; Dev Desk does not follow it" : entry.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var symbol: String {
        if entry.isSymlink { return "arrow.up.forward.square" }
        if entry.isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return "doc.text"
    }

    /// Bytes below a kilobyte, then KB, then MB — enough to judge a file, not a precise measure.
    static func readableSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

private struct FileViewer: View {
    let url: URL
    let path: String
    let root: URL

    var body: some View {
        let preview = FileReader.read(url, within: root)
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                if case .text(let contents) = preview {
                    ScrollView([.horizontal, .vertical]) {
                        Text(contents.isEmpty ? "This file is empty." : contents)
                            .font(DeskFont.mono(12))
                            .foregroundStyle(contents.isEmpty ? DeskColor.mutedInk : DeskColor.ink)
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    UnavailableView(reason: preview.message ?? "")
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(path)
                .font(DeskFont.mono(12))
                .foregroundStyle(DeskColor.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
            Button("Open in editor") { NSWorkspace.shared.open(url) }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}
