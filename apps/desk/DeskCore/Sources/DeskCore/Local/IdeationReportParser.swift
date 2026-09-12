import Foundation

/// Reads a dev:ideation report (skills/ideation/SKILL.md Phase 7): every verdict section's bullets become opportunities,
/// each carrying the gain and the cost, because the ranking is the ratio of the two.
enum IdeationReportParser {
    static let limits = "Ideation reads the code; no gain here was measured in a running app."

    private static let location = try! Regex(#"^[^\s·]+:\d+"#)
    /// The fields a confirmed bullet carries on its continuation lines, in the order the report writes them.
    private static let fieldKeys = ["gain:", "cost:", "doing nothing:", "touches:", "blocks:"]

    private enum Section {
        case confirmed, plausible, refuted, declined, tracked

        init?(heading: String) {
            let name = heading.dropFirst(3).uppercased()
            if name.hasPrefix("CONFIRMED") { self = .confirmed }
            else if name.hasPrefix("PLAUSIBLE") { self = .plausible }
            else if name.hasPrefix("REFUTED") { self = .refuted }
            else if name.hasPrefix("DECLINED BEFORE") { self = .declined }
            else if name.hasPrefix("ALREADY TRACKED") { self = .tracked }
            else { return nil }
        }

        var verdict: OpportunityVerdict {
            switch self {
            case .confirmed: return .confirmed
            case .plausible: return .plausible
            case .refuted: return .refuted
            case .declined: return .declined
            case .tracked: return .tracked
            }
        }

        var idLetter: String {
            switch self {
            case .confirmed: return "C"
            case .plausible: return "P"
            case .refuted: return "R"
            case .declined: return "D"
            case .tracked: return "T"
            }
        }
    }

    static func parse(_ markdown: String, runID: String) -> [Opportunity] {
        var opportunities: [Opportunity] = []
        var counts: [String: Int] = [:]
        var section: Section?
        var bullet: String?
        var continuation: [String] = []

        func flush() {
            guard let section, let text = bullet else { return }
            let index = (counts[section.idLetter] ?? 0) + 1
            counts[section.idLetter] = index
            opportunities.append(opportunity(text, continuation: continuation, section: section, index: index, runID: runID))
            bullet = nil
            continuation = []
        }

        for line in GitOutput.lines(markdown) {
            if line.hasPrefix("#") {
                flush()
                section = line.hasPrefix("## ") ? Section(heading: line) : nil
            } else if section != nil, line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                bullet = String(line.dropFirst(2))
            } else if bullet != nil, line.first == " " || line.first == "\t" {
                continuation.append(line)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            }
        }
        flush()
        return opportunities
    }

    /// The header's `Kinds: perf | security | quality`, when the report declares which kinds it covered.
    static func kinds(_ markdown: String) -> String? {
        for line in GitOutput.lines(markdown).prefix(5) {
            guard let range = line.range(of: "Kinds:") else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return Markdown.escape(value) }
        }
        return nil
    }

    private static func opportunity(_ text: String, continuation: [String], section: Section, index: Int, runID: String) -> Opportunity {
        let parts = text.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        // "current → proposed" is the confirmed bullet's shape; every other section states a claim alone.
        let head = parts.first ?? text
        let arrow = head.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
        var locations: [String] = []
        var rest: [String] = []
        for part in parts.dropFirst() {
            let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if bare.prefixMatch(of: location) != nil { locations.append(bare) } else { rest.append(part) }
        }
        // The bullet's own file:line comes first; a touches: path whose file is already cited with a line adds nothing.
        for bare in continuation.flatMap(bareLocations) where !locations.contains(bare) {
            locations.append(bare)
        }
        for path in continuation.flatMap({ paths(after: "touches:", in: $0) })
        where !locations.contains(where: { $0 == path || $0.hasPrefix("\(path):") }) {
            locations.append(path)
        }
        return Opportunity(
            id: "\(runID)-\(section.idLetter)\(index)", runID: runID,
            title: Markdown.escape(arrow.first ?? head),
            proposed: arrow.count > 1 ? Markdown.escape(arrow.dropFirst().joined(separator: " → ")) : nil,
            gain: field("gain:", in: continuation), cost: field("cost:", in: continuation),
            doingNothing: field("doing nothing:", in: continuation),
            summary: Markdown.escape(rest.joined(separator: " · ")), verdict: section.verdict,
            locations: locations, limits: limits)
    }

    /// The first line that carries this field, escaped; a value never runs past its own line into the one below.
    private static func field(_ key: String, in lines: [String]) -> String? {
        for line in lines {
            guard let value = value(after: key, in: line), !value.isEmpty else { continue }
            return Markdown.escape(value)
        }
        return nil
    }

    private static func paths(after key: String, in line: String) -> [String] {
        guard let value = value(after: key, in: line) else { return [] }
        return value.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            .filter { !$0.isEmpty }
    }

    /// The text after `key` on one line, ending where the next field on that line begins.
    private static func value(after key: String, in line: String) -> String? {
        guard let start = line.range(of: key) else { return nil }
        var value = line[start.upperBound...]
        let next = fieldKeys.filter { $0 != key }.compactMap { value.range(of: $0)?.lowerBound }.min()
        if let next { value = value[..<next] }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// A bare `file:line` sitting on its own continuation line, as the report's second line writes it.
    private static func bareLocations(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            .filter { $0.prefixMatch(of: location) != nil }
    }
}
