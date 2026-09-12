import Foundation

/// Bounded reads for repo files, so a hostile repo can't hang the app or leak a file outside it.
enum SafeFile {
    enum Read: Equatable {
        case text(String)
        case tooLarge
        case hardLink
        case skipped
    }

    /// Reads a regular file no larger than `maxBytes` whose real path stays inside `root`; a symlink, hard link, special file, oversize or outside path is refused.
    /// Every check runs on the one descriptor the bytes are then read from, so swapping the path mid-read changes nothing.
    static func read(_ url: URL, maxBytes: Int, within root: URL) -> Read {
        // O_NOFOLLOW refuses a symlink as the last component; O_NONBLOCK keeps a FIFO from hanging the open and is cleared before reading.
        let fd = url.withUnsafeFileSystemRepresentation { path in path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1 }
        guard fd >= 0 else { return .skipped }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return .skipped }
        // A second name can reach a file anywhere on the volume; no name at all means the file was replaced after the open.
        guard info.st_nlink == 1 else { return info.st_nlink > 1 ? .hardLink : .skipped }
        // open follows a symlinked parent directory, so it is the descriptor's own path that must sit inside the root.
        guard let base = realPath(ofDirectory: root), let path = realPath(of: fd),
              path.hasPrefix(base.hasSuffix("/") ? base : base + "/") else { return .skipped }
        if info.st_size > Int64(maxBytes) { return .tooLarge }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        // Read one byte past the cap so a file that grew after the size check is still caught.
        guard let data = try? handle.read(upToCount: maxBytes + 1) else { return .skipped }
        if data.count > maxBytes { return .tooLarge }
        return .text(String(decoding: data, as: UTF8.self))
    }

    private static func realPath(ofDirectory url: URL) -> String? {
        let fd = url.withUnsafeFileSystemRepresentation { path in path.map { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) } ?? -1 }
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return realPath(of: fd)
    }

    /// The kernel's path for an open descriptor, symlinks resolved, so the root and the file are spelled the same way.
    private static func realPath(of fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// The browser's listing rule, which walks paths rather than descriptors; a read still goes through `read`.
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == base || resolved.hasPrefix(base + "/")
    }
}
