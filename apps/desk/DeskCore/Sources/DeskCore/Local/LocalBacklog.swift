import Foundation

/// One item filed while there was no tracker to file into. `docs/guide/GETTING-STARTED.md` said that without
/// `gh` the filing doors cannot work, which is true of GitHub and was taken to mean the work cannot be
/// recorded at all — so a findings run on a repo with no reachable remote produced fifteen findings and nowhere to
/// put them (ADR 0027).
///
/// A file in the repo rather than app state: it survives, it is reviewable, it travels with a clone, and it is
/// what gets promoted to a real issue when a tracker turns up. The app writes it and never commits it — the
/// entry shows up in `git status` and committing stays the developer's.
public struct BacklogItem: Identifiable, Hashable {
    /// The file's own stem, which is also the card's id.
    public var id: String
    /// What it was filed from, e.g. a finding's `2026-08-31-C1`; empty when filed from nothing in particular.
    public var key: String
    public var title: String
    public var area: String?
    public var impact: String?
    public var complexity: String?
    /// "dev:findings run 2026-08-31", so a card can say where it came from.
    public var source: String?
    /// The issue it became, once a tracker existed and it was promoted. Never filed twice.
    public var issue: Int?
    /// `done` once the work is finished. A local card has no branch and no pull request, so git can never
    /// say this for it (ADR 0035 amendment): the card's own file is the only place the fact can live, and
    /// it travels with the clone the way `board.json` does not.
    public var status: String?
    /// What finished it, as the card records it — "2026-09-15 · 99564f1". Free text on purpose: a local card
    /// can be closed by a commit, by a decision, or by the work turning out to be unnecessary.
    public var resolved: String?
    /// The labels a filed issue would carry — `bug`, `security`, `impact:high` — so a local card filters and
    /// shows its type the way an issue does. `priority:` joins them when the run wrote it on its own line.
    public var labels: [String]
    /// The N of `order: N of M`, the place a findings run gave it among the slices; nil when it gave none.
    public var order: Int?
    /// What must be done before this can start (ADR 0060): other entries by key (`2026-10-01-C9`) and issues by
    /// `#N`, as written. Empty for `needs: none`.
    public var needs: [String]
    public var body: String
    public var path: String

    /// Finished work. Compared case-insensitively against the one spelling the doors write, so a card a
    /// person typed `Done` into reads the same as one a run wrote.
    public var isDone: Bool { status?.lowercased() == "done" }

    public init(id: String, key: String, title: String, area: String? = nil, impact: String? = nil,
                complexity: String? = nil, source: String? = nil, issue: Int? = nil, status: String? = nil,
                resolved: String? = nil, labels: [String] = [], order: Int? = nil, needs: [String] = [], body: String, path: String) {
        self.id = id
        self.key = key
        self.title = title
        self.area = area
        self.impact = impact
        self.complexity = complexity
        self.source = source
        self.issue = issue
        self.status = status
        self.resolved = resolved
        self.labels = labels
        self.order = order
        self.needs = needs
        self.body = body
        self.path = path
    }
}

public enum LocalBacklog {
    public static let folder = "docs/backlog"
    /// Where an entry goes once it is an issue. Kept as the record of where the issue came from, and moved out
    /// of the folder the board reads so there are never two editable copies of one item (ADR 0027).
    public static let filedFolder = "docs/backlog/filed"
    /// A backlog entry is prose about one item. Anything larger is not one.
    static let maxBytes = 256 * 1024

    // MARK: - Writing

    /// Writes one entry and returns its path. Refuses to overwrite: an item already filed is already filed,
    /// and a second press of the same button must not replace what the first one wrote.
    @discardableResult
    public static func write(projectPath: String, key: String, title: String, body: String,
                             area: String? = nil, source: String? = nil,
                             impact: String? = nil, complexity: String? = nil,
                             labels: [String] = [], priority: String? = nil) throws -> String {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName(key: key, title: title)
        let url = directory.appendingPathComponent("\(name).md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url.path }
        let text = document(key: key, title: title, body: body, area: area, source: source,
                            impact: impact, complexity: complexity, labels: labels, priority: priority)
        do {
            // Not `.atomic`: the guarantee that matters here is create-or-fail, and Foundation refuses to
            // combine the two. A replace-by-rename would be the one thing this must never do.
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            return url.path     // something else got there between the check and the write; theirs stands
        }
        return url.path
    }

    /// The entry itself: a header the app can read back, then the prose a person reads.
    /// `priority:` and `labels:` are the two lines a findings run writes, so a card the app filed and one a run
    /// filed read back the same; the priority is not repeated among the labels.
    static func document(key: String, title: String, body: String, area: String?, source: String?,
                         impact: String? = nil, complexity: String? = nil,
                         labels: [String] = [], priority: String? = nil) -> String {
        var header = ["---", "key: \(oneLine(key))", "title: \(oneLine(title))"]
        if let area { header.append("area: \(oneLine(area))") }
        if let priority = priority.map(oneLine), !priority.isEmpty { header.append("priority: \(priority)") }
        let rest = labels.map { oneLine($0).replacingOccurrences(of: ",", with: " ") }
            .filter { !$0.isEmpty && $0 != priority.map(oneLine) }
        if !rest.isEmpty { header.append("labels: \(rest.joined(separator: ", "))") }
        // Proposals for the developer to correct, the same two a filed issue carries (ADR 0020).
        header.append("impact: \(oneLine(impact ?? ""))")
        header.append("complexity: \(oneLine(complexity ?? ""))")
        if let source { header.append("source: \(oneLine(source))") }
        header.append("issue: ")
        header.append("---")
        return header.joined(separator: "\n") + "\n\n# \(oneLine(title))\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// `2026-08-31-C1-callback-fetch-returns-0-reminders`. The key leads so the file sorts with its run, and
    /// the slug is there so the folder is readable without opening anything.
    public static func fileName(key: String, title: String) -> String {
        let slug = slugify(title)
        let stem = [slugify(key), slug].filter { !$0.isEmpty }.joined(separator: "-")
        return stem.isEmpty ? "item-\(Int(Date().timeIntervalSince1970))" : String(stem.prefix(80))
    }

    static func slugify(_ text: String) -> String {
        let allowed = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        // ASCII only: a title in another script would otherwise become a row of dashes with no name in it.
        return String(allowed).split(separator: "-").joined(separator: "-")
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Reading

    /// Every entry in `docs/backlog/`, newest name last. A file that cannot be read safely is skipped rather
    /// than failing the whole board.
    public static func read(projectPath: String) -> [BacklogItem] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard case .text(let text) = SafeFile.read(url, maxBytes: maxBytes, within: root) else { return nil }
            return parse(text, id: String(name.dropLast(3)), path: url.path)
        }
    }

    static func parse(_ text: String, id: String, path: String) -> BacklogItem {
        var fields: [String: String] = [:]
        var body = text
        let lines = GitOutput.lines(text)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { fields[key] = value }
            }
            body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // The file opens with its title as a heading so it reads well on its own; on a card the title is
        // already the header, and saying it twice pushes the description down.
        if let title = fields["title"], body.hasPrefix("# \(title)") {
            body = String(body.dropFirst("# \(title)".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var labels = (fields["labels"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // `type:` is how a findings run says bug or epic when it writes no `labels:` line; the other types
        // (feature, task) are what an unlabelled card already reads as.
        if let type = fields["type"]?.lowercased(), ["bug", "epic"].contains(type), !labels.contains(type) {
            labels.append(type)
        }
        if let priority = fields["priority"]?.uppercased(), TaskFilter.priorityOrder.contains(priority), !labels.contains(priority) {
            labels.append(priority)
        }
        let order = fields["order"].flatMap { text in Int(text.prefix { $0.isNumber }) }
        return BacklogItem(id: id, key: fields["key"] ?? "", title: fields["title"] ?? id,
                           area: fields["area"], impact: fields["impact"], complexity: fields["complexity"],
                           source: fields["source"], issue: fields["issue"].flatMap(issueNumber),
                           status: fields["status"]?.lowercased(), resolved: fields["resolved"],
                           labels: labels, order: order, needs: needs(fields["needs"] ?? ""), body: body, path: path)
    }

    /// `2026-10-01-C9, #12` → both refs; `none` (what a run writes for an entry that can start now) → nothing.
    static func needs(_ line: String) -> [String] {
        line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !["none", "-", "—", "null"].contains($0.lowercased()) }
    }

    /// What File on GitHub asks `dev:create-issue` for. The card's labels go as real labels; one the repository
    /// lacks is offered, never created silently (ADR 0020) — the door's own rule, restated so the run cannot
    /// read "apply these" as permission to make them.
    public static func promotionRequest(for item: BacklogItem) -> String {
        let file = "\(folder)/\(item.id).md"
        let labels = item.labels.map(oneLine).filter { !$0.isEmpty }
        let labelling = labels.isEmpty ? "" : " Apply its labels: \(labels.joined(separator: ", ")) — each one this repository has; offer any it lacks, and never create one silently."
        // `needs: #N` in the issue is what Board enforces for an issue (ADR 0046); a key stays a key until its entry is
        // filed too (ADR 0060).
        let needs = item.needs.map(oneLine).filter { !$0.isEmpty }
        let waiting = needs.isEmpty ? "" : " Keep its line needs: \(needs.joined(separator: ", ")) in the issue's Scope, as written."
        return "\(oneLine(item.title)). The full description is in \(file); file it as written.\(labelling)\(waiting) Report the issue URL."
    }

    /// "#123", "123" or a URL ending in one — whatever the promoting run wrote back.
    static func issueNumber(_ text: String) -> Int? {
        let digits = text.split(whereSeparator: { !$0.isNumber }).last
        return digits.flatMap { Int($0) }
    }

    /// True when this item already has a name in `docs/backlog/`, so the card that filed it does not offer to
    /// file it again after a reload.
    public static func contains(key: String, projectPath: String) -> Bool {
        !key.isEmpty && read(projectPath: projectPath).contains { $0.key == key }
    }

    /// The entries that became issues, kept in `filed/`. Read so a `needs:` key can still name the issue its entry
    /// became (ADR 0060).
    public static func readFiled(projectPath: String) -> [BacklogItem] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let directory = root.appendingPathComponent(filedFolder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard case .text(let text) = SafeFile.read(url, maxBytes: maxBytes, within: root) else { return nil }
            return parse(text, id: String(name.dropLast(3)), path: url.path)
        }
    }

    /// The keys of entries that became issues. A finding filed locally and later promoted is still filed, and
    /// must not come back offering "Add to backlog" because its file moved.
    public static func filedKeys(projectPath: String) -> Set<String> {
        Set(readFiled(projectPath: projectPath).compactMap(\.key.nonEmpty))
    }

    // MARK: - Removing

    /// Moves an entry to the Trash rather than deleting it: a backlog item is a person's note, and the Trash is
    /// the undo the app does not otherwise have.
    public static func remove(atPath path: String, projectPath: String) throws {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let url = URL(fileURLWithPath: path)
        guard SafeFile.isInside(url, root.appendingPathComponent(folder, isDirectory: true)) else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    // MARK: - Promoting

    /// The issue a `dev:create-issue` run says it created. The door "produces an issue number, nothing else",
    /// but its last message is prose, and prose mentions other issues — "related to #42, filed as #87". A URL
    /// into this repository's issues is unambiguous, so it wins; otherwise the LAST `#N`, which is where a
    /// report of what it just did puts the number. Nil rather than a guess when there is neither.
    public static func issueNumber(inRunResult text: String, slug: String?) -> Int? {
        if let slug, !slug.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: slug)
            if let regex = try? NSRegularExpression(pattern: "github\\.com/\(escaped)/issues/(\\d+)", options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.matches(in: text, range: range).last,
                   let digits = Range(match.range(at: 1), in: text) {
                    return Int(text[digits])
                }
            }
        }
        guard let regex = try? NSRegularExpression(pattern: "#(\\d+)\\b") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let digits = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[digits])
    }

    /// Records the issue and moves the entry to `filed/`. After this GitHub owns the item; the file is history.
    public static func markFiled(_ number: Int, atPath path: String, projectPath: String) throws {
        try recordIssue(number, atPath: path, projectPath: projectPath)
        if let key = read(projectPath: projectPath).first(where: { $0.path == path })?.key.nonEmpty {
            try renameNeed(key, to: "#\(number)", projectPath: projectPath)
        }
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let source = URL(fileURLWithPath: path)
        let filed = root.appendingPathComponent(filedFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
        let destination = filed.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    /// The entries still waiting on `key` now name the issue it became (ADR 0060), so each issue they turn into
    /// reads `needs: #N` — the line Board enforces for an issue. Only the header's `needs:` line is touched.
    static func renameNeed(_ key: String, to ref: String, projectPath: String) throws {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        for item in read(projectPath: projectPath) where item.needs.contains(key) {
            let url = URL(fileURLWithPath: item.path)
            guard case .text(let text) = SafeFile.read(url, maxBytes: maxBytes, within: root) else { continue }
            var lines = GitOutput.lines(text)
            guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
                  let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }),
                  let index = lines[1..<end].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("needs:") })
            else { continue }
            let renamed = item.needs.map { $0 == key ? ref : $0 }
            lines[index] = "needs: \(renamed.joined(separator: ", "))"
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
        }
    }

    /// Records the issue an entry became. Written by the app after `dev:create-issue` reports a number, so the
    /// entry is never filed to GitHub twice and the card can link to it.
    public static func recordIssue(_ number: Int, atPath path: String, projectPath: String) throws {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        let url = URL(fileURLWithPath: path)
        guard SafeFile.isInside(url, root), case .text(let text) = SafeFile.read(url, maxBytes: maxBytes, within: root) else { return }
        var lines = GitOutput.lines(text)
        if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("issue:") }) {
            lines[index] = "issue: #\(number)"
        } else if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.insert("issue: #\(number)", at: 1)
        } else {
            return
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}
