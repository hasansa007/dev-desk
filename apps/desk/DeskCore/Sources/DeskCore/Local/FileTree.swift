import Foundation

/// One entry of a directory listing. A symlink is listed so the folder is not silently incomplete,
/// but it is never expanded or read: that is `SafeFile`'s rule, carried into the browser.
public struct FileEntry: Identifiable, Hashable {
    /// The path relative to the project root, which is also its identity in the tree.
    public var id: String
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool
    /// Bytes, for a regular file that reported a size.
    public var size: Int?

    public init(id: String, name: String, isDirectory: Bool, isSymlink: Bool, size: Int? = nil) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
    }

    /// A symlinked folder is not a folder you can open here, so it never offers a disclosure arrow.
    public var isExpandable: Bool { isDirectory && !isSymlink }
}

/// Lists one directory at a time. Nothing walks the tree: a repository with node_modules opens as fast as an empty one.
public enum FileTree {
    /// Directories first, then files, each case-insensitively by name — the order Finder shows.
    public static func list(_ directory: URL, within root: URL) -> [FileEntry] {
        guard SafeFile.isInside(directory, root) else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .nameKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []) else { return [] }

        let entries = contents.compactMap { url -> FileEntry? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink ?? false
            let isDirectory = values?.isDirectory ?? false
            return FileEntry(id: relativePath(of: url, in: root), name: values?.name ?? url.lastPathComponent,
                             isDirectory: isDirectory, isSymlink: isSymlink,
                             size: isDirectory ? nil : values?.fileSize)
        }
        return entries.sorted { left, right in
            if left.isDirectory != right.isDirectory { return left.isDirectory }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    /// The path shown in the tree and used as an id; an absolute path for anything not under the root.
    static func relativePath(of url: URL, in root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return path }
        return String(path.dropFirst(base.count + 1))
    }
}
