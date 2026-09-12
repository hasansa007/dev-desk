import Foundation

/// What the browser can show for one file. Binary and oversize say so rather than rendering bytes as text.
public enum FilePreview: Equatable {
    case text(String)
    case binary
    case tooLarge(Int)
    case unreadable(String)

    public var message: String? {
        switch self {
        case .text: return nil
        case .binary: return "This file is binary, so there is nothing to show as text."
        case .tooLarge(let cap): return "This file is larger than \(cap / 1024) KB, so it is not read."
        case .unreadable(let reason): return reason
        }
    }
}

public enum FileReader {
    public static let maxBytes = 262_144

    /// Reads a regular file inside `root`, refusing a symlink and anything resolving outside it — `SafeFile`'s rule.
    /// A NUL byte in what was read means binary; text is decoded leniently, as a viewer must.
    public static func read(_ url: URL, maxBytes: Int = maxBytes, within root: URL) -> FilePreview {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else {
            return .unreadable("This file could not be read.")
        }
        if values.isSymbolicLink == true { return .unreadable("This is a symbolic link, so it is not followed.") }
        guard values.isRegularFile == true else { return .unreadable("This is not a regular file.") }
        guard SafeFile.isInside(url, root) else { return .unreadable("This file resolves outside the project, so it is not read.") }
        if let size = values.fileSize, size > maxBytes { return .tooLarge(maxBytes) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable("This file could not be opened.") }
        defer { try? handle.close() }
        // One byte past the cap, so a file that grew after the size check is still caught.
        guard let data = try? handle.read(upToCount: maxBytes + 1) else { return .unreadable("This file could not be read.") }
        if data.count > maxBytes { return .tooLarge(maxBytes) }
        if data.contains(0) { return .binary }
        return .text(String(decoding: data, as: UTF8.self))
    }
}
