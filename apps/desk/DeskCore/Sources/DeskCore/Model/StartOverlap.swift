import Foundation

/// A task In progress that changes code this one is about to (ADR 0046, decision 11). Same function asks before
/// Start; same file only notes it — git merges different code in one file cleanly.
public struct StartOverlap: Equatable, Hashable {
    public var issue: Int
    public var file: String
    /// The shared function, when both sides name it.
    public var code: String?
    public var isSameCode: Bool { code != nil }
}

public enum StartOverlaps {
    /// `touches:` lines of an issue body — the findings door's coordination line, carried into `## Scope`.
    public static func touches(inBody body: String) -> [CodeTouch] {
        body.components(separatedBy: .newlines).flatMap { line -> [CodeTouch] in
            guard let range = line.range(of: "touches:") else { return [] }
            return FindingsReportParser.touches(String(line[range.upperBound...])).map {
                CodeTouch(file: $0.file, code: $0.code.map(function))
            }
        }
    }

    /// Every In-progress task (not this one) whose `touches:` or branch changes meet this task's `touches:`. A task
    /// with no `touches:` of its own can meet nothing — there is nothing to compare, and guessing would nag.
    public static func find(_ task: DeskTask, among tasks: [DeskTask]) -> [StartOverlap] {
        guard !task.touches.isEmpty else { return [] }
        var found: [StartOverlap] = []
        for other in tasks where other.column == .inProgress && other.id != task.id {
            guard let number = other.issueNumber else { continue }
            let changed = other.changes.value?.files.map(\.id) ?? []
            for mine in task.touches {
                if let theirs = other.touches.first(where: { sameFile($0.file, mine.file) && $0.code != nil && $0.code == mine.code }) {
                    found.append(StartOverlap(issue: number, file: theirs.file, code: theirs.code))
                } else if other.touches.contains(where: { sameFile($0.file, mine.file) }) || changed.contains(where: { sameFile($0, mine.file) }) {
                    found.append(StartOverlap(issue: number, file: mine.file, code: nil))
                }
            }
        }
        // One entry per issue and file, a shared function beating a shared file.
        var best: [String: StartOverlap] = [:]
        for overlap in found {
            let key = "\(overlap.issue)|\((overlap.file as NSString).lastPathComponent)"
            if best[key] == nil || (overlap.isSameCode && !(best[key]!.isSameCode)) { best[key] = overlap }
        }
        return best.values.sorted { ($0.isSameCode ? 0 : 1, $0.issue, $0.file) < ($1.isSameCode ? 0 : 1, $1.issue, $1.file) }
    }

    /// `web/app/api/tts/route.js` and `route.js` name one file when one ends the other at a path boundary.
    static func sameFile(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix("/" + b) || b.hasSuffix("/" + a)
    }

    /// `ttsSynthesize()` (gate by default)` → `ttsSynthesize`: the name, without call parens or a trailing note.
    static func function(_ code: String) -> String {
        let cut = code.split(whereSeparator: { $0 == "`" || $0 == "(" }).first.map(String.init) ?? code
        return cut.trimmingCharacters(in: .whitespaces)
    }
}

/// `.devdesk/waits.json` — "queue #816 after #814" chosen at Start (ADR 0046). The Waits-for rule reads it beside an
/// issue's own `needs:` lines; local, like the Plan's order, because it is a decision about this developer's queue.
public struct LocalWaits: Codable, Equatable, Sendable {
    public static let relativePath = ".devdesk/waits.json"
    /// Issue number (as a string key) → the issues it waits for.
    public var waits: [String: [Int]]

    public init(waits: [String: [Int]] = [:]) { self.waits = waits }

    public static func read(projectRoot: URL) -> LocalWaits {
        guard let data = try? Data(contentsOf: projectRoot.appendingPathComponent(relativePath)),
              let waits = try? JSONDecoder().decode(LocalWaits.self, from: data) else { return LocalWaits() }
        return waits
    }

    public func write(projectRoot: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let url = projectRoot.appendingPathComponent(Self.relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func adding(_ blocker: Int, to issue: Int) -> LocalWaits {
        var copy = self
        var list = copy.waits[String(issue)] ?? []
        if !list.contains(blocker) { list.append(blocker) }
        copy.waits[String(issue)] = list
        return copy
    }
}
