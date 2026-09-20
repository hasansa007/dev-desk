import Foundation
import ImageIO
import Observation

/// What a project's badge shows. The default is `.initials`, and it is never stored — an absent entry *is*
/// the default, so a project the developer never touched has no state to migrate.
public enum ProjectMark: Codable, Hashable, Sendable {
    case initials
    case color(hex: String)
    /// The file name inside the app's own image folder, never the path the developer picked: the original
    /// may be moved or thrown away, and the badge has to survive that.
    case image(file: String)
}

/// A project's resolved identity — what a badge draws, with nothing left to look up.
public struct ProjectIdentity: Codable, Hashable, Sendable {
    /// Two letters at most; empty only when the name has no letters or digits at all.
    public var initials: String
    /// `#RRGGBB`. The mark's colour when one was chosen, otherwise the one derived from `ProjectRef.id`.
    public var colorHex: String
    /// Set only for an image mark, and only while the copied file is still on disk.
    public var imagePath: String?

    public var isImage: Bool { imagePath != nil }

    public init(initials: String, colorHex: String, imagePath: String? = nil) {
        self.initials = initials
        self.colorHex = colorHex
        self.imagePath = imagePath
    }
}

public enum ProjectIdentityError: LocalizedError {
    case notAnImage
    case tooLarge(bytes: Int)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAnImage: return "That file is not an image Dev Desk can read."
        case .tooLarge(let bytes):
            let mb = Double(bytes) / 1_048_576
            return String(format: "That image is %.0f MB. Pick one under %d MB.", mb, ProjectIdentityStore.imageSizeLimitMB)
        case .copyFailed(let reason): return "The image could not be copied in: \(reason)"
        }
    }
}

// MARK: - Derivation (pure; the testable half)

extension ProjectIdentity {
    /// The identity palette. Green and amber are RESERVED for running and waiting (brief, 2026-09-20): a
    /// project whose badge were green would read as a project with something running, so every hue here sits
    /// outside `reservedHues`, which `ProjectIdentityTests` asserts rather than trusts.
    public static let palette: [String] = [
        "#9CC0FF", // sky
        "#B8A7F2", // violet
        "#F2A7C3", // pink
        "#8FD3E8", // cyan
        "#F0A0A0", // coral
        "#C9CFD9", // steel
    ]

    /// Amber (#E7C067, hue 43°) through green (#7FD19B, hue 143°) — the status band no identity may enter.
    public static let reservedHues: ClosedRange<Double> = 30...175

    /// Deterministic from `ProjectRef.id` (FNV-1a), never from a counter or the order projects were opened:
    /// the same project has to wear the same colour on every machine and after every relaunch.
    public static func paletteHex(forID id: String) -> String {
        palette[Int(fnv1a(id) % UInt64(palette.count))]
    }

    /// `dev-desk` → `DS`, `studyhub` → `ST`. Separators are `-`, `_`, `.`, space and slash; a single word
    /// falls back to its first two letters because there is nothing else to take a second letter from.
    public static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { !$0.isEmpty }
        guard let first = words.first else { return "" }
        if words.count >= 2, let second = words.dropFirst().first {
            return (String(first.prefix(1)) + String(second.prefix(1))).uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }

    /// Hue in degrees, for the palette guard. Returns nil for grey (no hue) and for unparseable hex.
    public static func hue(ofHex hex: String) -> Double? {
        guard let (r, g, b) = rgb(ofHex: hex) else { return nil }
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        guard delta > 0.0001 else { return nil }
        let h: Double
        switch maxC {
        case r: h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: h = 60 * (((b - r) / delta) + 2)
        default: h = 60 * (((r - g) / delta) + 4)
        }
        return h < 0 ? h + 360 : h
    }

    /// Saturation, 0…1 (HSV). A near-grey carries no hue, so the reserved band cannot judge it.
    public static func saturation(ofHex hex: String) -> Double? {
        guard let (r, g, b) = rgb(ofHex: hex) else { return nil }
        let maxC = max(r, g, b)
        guard maxC > 0 else { return 0 }
        return (maxC - min(r, g, b)) / maxC
    }

    /// A chosen colour is refused when it lands in the status band; an unsaturated near-grey is allowed,
    /// because grey never reads as running.
    public static func isReserved(hex: String) -> Bool {
        guard let s = saturation(ofHex: hex), s > 0.18, let h = hue(ofHex: hex) else { return false }
        return reservedHues.contains(h)
    }

    /// sRGB 0…1, for the badge: the palette is hex data rather than a token, so the view needs a way in.
    public static func rgbComponents(ofHex hex: String) -> (Double, Double, Double)? { rgb(ofHex: hex) }

    static func rgb(ofHex hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}

// MARK: - Store

/// Per-project identity, persisted by `ProjectRef.id` exactly as `RecentProjectsStore` persists its list.
/// `@Observable` so a badge redraws the moment the picker writes — the strip and the rail draw the same
/// project at once, and a badge that lagged its own picker would look broken.
@MainActor
@Observable
public final class ProjectIdentityStore {
    /// Anything bigger is a photo, not an icon, and decoding it on the strip would stall the window.
    public nonisolated static let imageSizeLimitMB = 12

    public static let shared = ProjectIdentityStore()

    private var marks: [String: ProjectMark] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    /// The app's own folder, so a badge survives the picked file moving or being deleted.
    @ObservationIgnored public let imagesDirectory: URL

    public init(defaults: UserDefaults = .standard,
                key: String = "desk.projectIdentities",
                imagesDirectory: URL? = nil) {
        self.defaults = defaults
        self.key = key
        self.imagesDirectory = imagesDirectory ?? Self.defaultImagesDirectory()
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: ProjectMark].self, from: data) {
            marks = decoded
        }
    }

    public func identity(for ref: ProjectRef, name: String) -> ProjectIdentity {
        let initials = ProjectIdentity.initials(from: name)
        switch marks[ref.id] {
        case .color(let hex):
            return ProjectIdentity(initials: initials, colorHex: hex)
        case .image(let file):
            let url = imagesDirectory.appendingPathComponent(file)
            // A file that has gone missing falls back rather than drawing a hole.
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ProjectIdentity(initials: initials, colorHex: ProjectIdentity.paletteHex(forID: ref.id))
            }
            return ProjectIdentity(initials: initials,
                                   colorHex: ProjectIdentity.paletteHex(forID: ref.id),
                                   imagePath: url.path)
        case .initials, nil:
            return ProjectIdentity(initials: initials, colorHex: ProjectIdentity.paletteHex(forID: ref.id))
        }
    }

    public func mark(for ref: ProjectRef) -> ProjectMark { marks[ref.id] ?? .initials }

    /// A reserved hue is refused silently rather than saved — the picker only offers the palette, so this
    /// guards the API, not the developer.
    public func setColor(_ hex: String, for ref: ProjectRef) {
        guard !ProjectIdentity.isReserved(hex: hex) else { return }
        write(.color(hex: hex), for: ref)
    }

    /// Copies the picked file into the app's own folder and points the mark at the copy.
    public func setImage(from source: URL, for ref: ProjectRef) throws {
        let manager = FileManager.default
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.imageSizeLimitMB * 1_048_576 else { throw ProjectIdentityError.tooLarge(bytes: size) }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else { throw ProjectIdentityError.notAnImage }

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        // Named by the hash of the ref, never by the project's own path: a path can hold "/" and a name can
        // hold anything at all.
        let file = String(format: "%016llx", ProjectIdentity.fnv1a(ref.id)) + "-" + String(UUID().uuidString.prefix(8)) + "." + ext
        let destination = imagesDirectory.appendingPathComponent(file)
        do {
            try manager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: destination)
        } catch {
            throw ProjectIdentityError.copyFailed(error.localizedDescription)
        }
        removeStoredImage(for: ref)
        write(.image(file: file), for: ref)
    }

    public func reset(_ ref: ProjectRef) {
        removeStoredImage(for: ref)
        marks[ref.id] = nil
        persist()
    }

    private func write(_ mark: ProjectMark, for ref: ProjectRef) {
        if case .image = mark {} else { removeStoredImage(for: ref) }
        marks[ref.id] = mark
        persist()
    }

    /// The copy is ours, so dropping the mark drops the file too; leaving it would grow the folder forever.
    private func removeStoredImage(for ref: ProjectRef) {
        guard case .image(let file) = marks[ref.id] else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(marks) { defaults.set(data, forKey: key) }
    }

    private static func defaultImagesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DevDesk/ProjectIcons", isDirectory: true)
    }
}
