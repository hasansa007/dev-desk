import DeskCore
import SwiftUI

/// The project's own files, down the right of whatever you are looking at — the project folder's, or one of its
/// worktrees', picked in the header. Listed one directory at a time, so a repository carrying node_modules opens
/// as fast as an empty one. Tapping one selects it; reading it is `FileViewerPane`'s job, which `ContentRouter`
/// places beside the work rather than under the tree. A listing is a snapshot: Refresh reads it again.
struct FilesPanel: View {
    @Bindable var model: ProjectWindowModel
    @State private var expanded: Set<String> = []
    @State private var children: [String: [FileEntry]] = [:]

    private var root: URL? { model.filesRoot }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let root {
                tree(root)
            } else {
                UnavailableView(reason: "Sample projects have no folder on disk, so there is nothing to browse.")
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeskColor.surface)
        .overlay(alignment: .leading) { Rectangle().fill(DeskColor.border).frame(width: 1) }
        .task(id: model.ref.id) { await model.loadFilesWorktrees() }
        // Another worktree is another tree: nothing listed or expanded in the old one carries over.
        .task(id: root?.path) {
            expanded = []
            children = [:]
            if let root { children[""] = FileTree.list(root, within: root) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Files").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(DeskColor.ink)
            if model.filesWorktrees.count > 1 {
                worktreeMenu
            } else {
                Text(model.snapshot?.project.name ?? "")
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if let root {
                Button { Task { await refresh(root) } } label: { Image(systemName: "arrow.clockwise").imageScale(.small) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Read the folder again")
                    .accessibilityLabel("Refresh")
            }
            Button("Close") { model.toggleFiles() }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    /// Which worktree the tree shows, named by its branch — the branch is what you are choosing between.
    private var worktreeMenu: some View {
        Menu {
            ForEach(model.filesWorktrees, id: \.path) { worktree in
                let tag = model.isProjectFolder(worktree) ? nil : worktree.path
                Button {
                    model.filesWorktreePath = tag
                } label: {
                    if tag == model.filesWorktreePath { Label(label(worktree), systemImage: "checkmark") } else { Text(label(worktree)) }
                }
                .help(worktree.path)
            }
        } label: {
            Text("\(currentLabel) ▾")
                .font(DeskFont.mono(11))
                .foregroundStyle(DeskColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(root?.path ?? "")
    }

    private var currentLabel: String {
        let current = model.filesWorktrees.first { worktree in
            model.isProjectFolder(worktree) ? model.filesWorktreePath == nil : worktree.path == model.filesWorktreePath
        }
        return current.map(label) ?? (root?.lastPathComponent ?? "")
    }

    /// The branch, or the folder's name when it has none (a detached HEAD).
    private func label(_ worktree: Worktree) -> String {
        let folder = URL(fileURLWithPath: worktree.path).lastPathComponent
        return worktree.branch ?? "\(folder) (detached)"
    }

    /// Reads the worktree list and every folder on screen again. A folder that is gone collapses with it.
    private func refresh(_ root: URL) async {
        await model.loadFilesWorktrees()
        guard model.filesRoot == root else { return }  // the chosen worktree vanished: the root task relists
        var fresh: [String: [FileEntry]] = ["": FileTree.list(root, within: root)]
        var stillThere: Set<String> = []
        for id in expanded.sorted() {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            fresh[id] = FileTree.list(root.appendingPathComponent(id), within: root)
            stillThere.insert(id)
        }
        children = fresh
        expanded = stillThere
    }

    private func tree(_ root: URL) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows(), id: \.entry.id) { row in
                    FileRow(entry: row.entry, depth: row.depth,
                            isExpanded: expanded.contains(row.entry.id),
                            isSelected: row.entry.id == model.selectedFilePath) {
                        select(row.entry, root: root)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The visible rows: the root's entries, with an expanded directory's children spliced in beneath it.
    private func rows() -> [(entry: FileEntry, depth: Int)] {
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
