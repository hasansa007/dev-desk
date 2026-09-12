import Foundation

/// Bounded, symlink-refusing reads for repo files, so a hostile repo can't hang the app or leak a file outside it.
enum SafeFile {
    enum Read: Equatable {
        case text(String)
        case tooLarge
        case skipped
    }

    /// Reads a regular file no larger than `maxBytes` whose resolved path stays inside `root`; a symlink, oversize or outside path is refused.
    static func read(_ url: URL, maxBytes: Int, within root: URL) -> Read {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
              values.isSymbolicLink != true, values.isRegularFile == true else { return .skipped }
        guard isInside(url, root) else { return .skipped }
        if let size = values.fileSize, size > maxBytes { return .tooLarge }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .skipped }
        defer { try? handle.close() }
        // Read one byte past the cap so a file that grew after the size check is still caught.
        guard let data = try? handle.read(upToCount: maxBytes + 1) else { return .skipped }
        if data.count > maxBytes { return .tooLarge }
        return .text(String(decoding: data, as: UTF8.self))
    }

    /// Shared with the file browser, so one rule decides what counts as inside the repository.
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == base || resolved.hasPrefix(base + "/")
    }
}
