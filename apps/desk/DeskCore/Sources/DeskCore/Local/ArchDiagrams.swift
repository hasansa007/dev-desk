import Foundation

/// A `dev:arch` diagram: one self-contained HTML file in `docs/arch/`, named by the sidecar JSON that was written beside it.
public struct ArchDiagram: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var url: URL

    public init(id: String, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// What `dev:arch` left in a repository. The app only lists and displays these; nothing here draws or writes one.
public enum ArchDiagrams {
    public static let folder = "docs/arch"
    static let maxSidecarBytes = 262_144

    /// The diagrams a repository has, by file name. Empty is the ordinary answer for a repo that has never run `dev:arch`.
    public static func list(repositoryRoot: String) -> [ArchDiagram] {
        let directory = URL(fileURLWithPath: repositoryRoot, isDirectory: true).appendingPathComponent(folder)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        return names.filter { $0.hasSuffix(".html") }.map { name in
            let stem = String(name.dropLast(5))
            return ArchDiagram(id: stem,
                               title: title(stem: stem, in: directory, siblings: names) ?? readableName(stem),
                               url: directory.appendingPathComponent(name))
        }
    }

    /// `meta.title` from the sidecar `<stem>.<kind>.json`; nil when there is none, or it says nothing useful.
    private static func title(stem: String, in directory: URL, siblings: [String]) -> String? {
        guard let sidecar = siblings.first(where: { $0.hasPrefix("\(stem).") && $0.hasSuffix(".json") }),
              case .text(let text) = SafeFile.read(directory.appendingPathComponent(sidecar),
                                                   maxBytes: maxSidecarBytes, within: directory),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let meta = object["meta"] as? [String: Any],
              let title = meta["title"] as? String, !title.isEmpty else { return nil }
        return title
    }

    /// "dev-family" reads as "Dev family": the file name is the fallback label, tidied rather than shown raw.
    static func readableName(_ stem: String) -> String {
        let words = stem.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = words.first else { return stem }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }
}
