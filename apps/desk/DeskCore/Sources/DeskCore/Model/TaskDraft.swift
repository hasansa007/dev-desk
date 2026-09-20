import Foundation

/// A task as Add Task collects it (ADR 0045): a title, the bullets that become its `## Done when`, and the
/// description around them. One body for both destinations, so a GitHub issue and a `docs/backlog/` entry read
/// alike and `/dev` finds its acceptance list in the same place either way.
public struct TaskDraft: Equatable {
    public var title: String
    public var bullets: [String]
    public var description: String

    public init(title: String, bullets: [String] = [], description: String = "") {
        self.title = title
        self.bullets = bullets
        self.description = description
    }

    /// The sheet's multi-line field, one bullet per line.
    public init(title: String, bulletsText: String, description: String) {
        self.init(title: title, bullets: Self.bullets(from: bulletsText), description: description)
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// One bullet per non-empty line. A leading `-`, `*`, `•`, `[ ]` or `1.` / `1)` is how the line was typed,
    /// not what it says — kept, it would render as `- - item`.
    public static func bullets(from text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            var rest = Substring(line.trimmingCharacters(in: .whitespaces))
            for marker in ["- [ ] ", "* [ ] ", "[ ] ", "- ", "* ", "• "] where rest.hasPrefix(marker) {
                rest = rest.dropFirst(marker.count)
                break
            }
            if let dot = rest.firstIndex(where: { $0 == "." || $0 == ")" }), dot != rest.startIndex,
               rest[rest.startIndex..<dot].allSatisfy(\.isNumber) {
                rest = rest[rest.index(after: dot)...]
            }
            let item = rest.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    /// The description, then `## Done when` — each part only when it has something in it.
    public var body: String {
        var parts: [String] = []
        let prose = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prose.isEmpty { parts.append(prose) }
        if !bullets.isEmpty { parts.append("## Done when\n" + bullets.map { "- \($0)" }.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }
}

/// Where Add Task will put the task, resolved before anything is typed (ADR 0045 step 2).
public enum TaskDestination: Equatable {
    case github(slug: String)
    /// No reachable tracker; the reason is the GitHub connection's own short one ("not signed in").
    case local(reason: String)

    /// A tracker is reachable exactly when the snapshot carries a slug — `LocalGitDataSource` sets it from
    /// GitHub's data, which exists only when the remote resolved, gh is signed in and the issues read worked.
    public static func resolve(slug: String?, trackerUnavailable: String?) -> TaskDestination {
        if let slug, !slug.isEmpty { return .github(slug: slug) }
        return .local(reason: trackerUnavailable ?? "no GitHub remote")
    }

    public var isGitHub: Bool { if case .github = self { return true } else { return false } }

    public var label: String {
        switch self {
        case .github(let slug): return "→ GitHub issue in \(slug)"
        case .local(let reason): return "→ \(LocalBacklog.folder) (\(reason))"
        }
    }
}

/// An open item that may already be this task. A proposal only: the developer decides (ADR 0045 step 3).
public struct DuplicateCandidate: Identifiable, Equatable, Decodable {
    public var number: Int?
    public var title: String
    /// The `docs/backlog/` entry, when the match is local.
    public var localEntry: String?

    public var id: String { number.map { "#\($0)" } ?? "local:\(localEntry ?? title)" }

    public init(number: Int?, title: String, localEntry: String? = nil) {
        self.number = number
        self.title = title
        self.localEntry = localEntry
    }

    enum CodingKeys: String, CodingKey { case number, title }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        localEntry = nil
    }
}

/// The plain search behind the duplicate proposal — no agent, so it answers while the sheet is open.
public enum DuplicateSearch {
    /// The few words worth searching for. GitHub's search ANDs every term, so a whole sentence matches nothing;
    /// the three longest distinct words of four letters or more carry the subject. Letters are Unicode's, so an
    /// Arabic title searches as well as an English one.
    public static func keywords(_ title: String) -> [String] {
        var seen = Set<String>()
        let words = title.components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0.lowercased()) }
            .filter { seen.insert($0.lowercased()).inserted }
        return Array(words.sorted { $0.count > $1.count }.prefix(3))
    }

    private static let stopWords: Set<String> = ["that", "this", "with", "from", "when", "should", "would", "could",
                                                 "there", "their", "into", "only", "have", "make", "does", "what"]

    /// `gh` arguments for the open issues matching the title's keywords, or nil when it has none to search for.
    public static func arguments(slug: String, title: String) -> [String]? {
        let words = keywords(title)
        guard !words.isEmpty else { return nil }
        return ["issue", "list", "--repo", slug, "--state", "open", "--limit", "5",
                "--search", words.joined(separator: " ") + " in:title,body", "--json", "number,title"]
    }

    public static func parse(_ json: String) -> [DuplicateCandidate] {
        (try? JSONDecoder().decode([DuplicateCandidate].self, from: Data(json.utf8))) ?? []
    }

    /// The same proposal without a tracker: entries whose title shares the keywords — all of them when the title
    /// has one or two, at least two otherwise. Filed entries are GitHub's now, and done ones are finished.
    public static func local(_ items: [BacklogItem], title: String) -> [DuplicateCandidate] {
        let words = keywords(title).map { $0.lowercased() }
        guard !words.isEmpty else { return [] }
        let needed = min(2, words.count)
        var matches: [DuplicateCandidate] = []
        for item in items where item.issue == nil && !item.isDone {
            let text = item.title.lowercased()
            let shared = words.filter { text.contains($0) }.count
            if shared >= needed { matches.append(DuplicateCandidate(number: nil, title: item.title, localEntry: item.id)) }
            if matches.count == 5 { break }
        }
        return matches
    }
}

/// `gh issue create` for a draft — no agent run, no guessed labels (ADR 0045 step 4).
public enum IssueCreate {
    public static func arguments(slug: String, draft: TaskDraft, milestone: String?, labels: [String] = []) -> [String] {
        var arguments = ["issue", "create", "--repo", slug, "--title", draft.trimmedTitle, "--body", draft.body]
        // The ratings the developer chose in the sheet, never guessed ones (ADR 0020).
        if !labels.isEmpty { arguments += ["--label", labels.joined(separator: ",")] }
        if let milestone = milestone?.trimmingCharacters(in: .whitespacesAndNewlines), !milestone.isEmpty {
            arguments += ["--milestone", milestone]
        }
        return arguments
    }

    /// `gh issue create` prints the new issue's URL; its number is the last path component after `/issues/`.
    /// Nil when the output names none — the issue it made is never guessed (ADR 0027).
    public static func number(fromOutput output: String) -> Int? {
        guard let range = output.range(of: "/issues/", options: .backwards) else { return nil }
        return Int(output[range.upperBound...].prefix { $0.isNumber })
    }
}
