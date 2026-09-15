import Foundation

/// A `dev:arch` diagram: one self-contained HTML file in `docs/arch/`, named by the sidecar JSON that was written beside it.
public struct ArchDiagram: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var url: URL
    /// The `dev:arch` type this was drawn as — `architecture`, `workflow`, `dataflow`, `sequence`, `lifecycle` —
    /// read from the sidecar's `diagram_type`. nil when there is no readable sidecar, so a caller falls back.
    public var kind: String?
    /// The HTML file's modification time, so the newest diagram of a kind can be chosen when a repository has
    /// drawn the same kind more than once. `.distantPast` when the file's date could not be read.
    public var modifiedAt: Date

    public init(id: String, title: String, url: URL, kind: String? = nil, modifiedAt: Date = .distantPast) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.modifiedAt = modifiedAt
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
            let url = directory.appendingPathComponent(name)
            let sidecar = readSidecar(stem: stem, in: directory, siblings: names)
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            return ArchDiagram(id: stem,
                               title: sidecar.title ?? readableName(stem),
                               url: url,
                               kind: sidecar.kind,
                               modifiedAt: modified ?? .distantPast)
        }
    }

    /// The five diagram types `dev:arch` draws, in the skill's own order. The Diagrams screen lists exactly
    /// these whether or not any have been drawn, so a kind is a place to generate into, not only a file to show.
    public static let kinds = ["architecture", "workflow", "dataflow", "sequence", "lifecycle"]

    /// The newest diagram of `kind` in a repository, or nil when none has been drawn. A repository that ran the
    /// same kind twice keeps both files; the most recently written one is the one the kind's item shows.
    public static func newest(kind: String, repositoryRoot: String) -> ArchDiagram? {
        list(repositoryRoot: repositoryRoot)
            .filter { $0.kind == kind }
            .max { $0.modifiedAt < $1.modifiedAt }
    }

    /// What the sidecar `<stem>.<kind>.json` says about a diagram: its `meta.title` and its `diagram_type`. Both
    /// are optional — a diagram may have no sidecar, or one that says nothing useful — so each caller falls back.
    private static func readSidecar(stem: String, in directory: URL, siblings: [String]) -> (title: String?, kind: String?) {
        guard let sidecar = siblings.first(where: { $0.hasPrefix("\(stem).") && $0.hasSuffix(".json") }),
              case .text(let text) = SafeFile.read(directory.appendingPathComponent(sidecar),
                                                   maxBytes: maxSidecarBytes, within: directory),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return (nil, nil) }
        let meta = object["meta"] as? [String: Any]
        let rawTitle = meta?["title"] as? String
        let title = (rawTitle?.isEmpty == false) ? rawTitle : nil
        let rawKind = object["diagram_type"] as? String
        let kind = (rawKind?.isEmpty == false) ? rawKind : nil
        return (title, kind)
    }

    /// "dev-family" reads as "Dev family": the file name is the fallback label, tidied rather than shown raw.
    static func readableName(_ stem: String) -> String {
        let words = stem.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = words.first else { return stem }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }
}
