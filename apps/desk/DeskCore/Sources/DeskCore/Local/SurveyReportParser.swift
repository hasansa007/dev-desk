import Foundation

/// Reads a dev:survey report (skills/survey/SKILL.md): CONFIRMED, PLAUSIBLE and ALREADY TRACKED bullets become findings.
enum SurveyReportParser {
    static let limits = "Survey checks code only; nothing here was reproduced in a running app."

    /// "File.swift:88", and the line ranges a report writes just as often: "File.swift:54-66".
    private static let location = try! Regex(#"^[^\s·`,;]+:\d+(-\d+)?"#)
    /// "1. ", "12. " — a ranked list is the same list. A surveyor that ranks CONFIRMED by cost writes
    /// numbers, and reading only dashes dropped twelve confirmed defects while keeping seven held ones.
    private static let numbered = try! Regex(#"^\d+\.[ \t]+"#)

    private enum Section: Hashable {
        case confirmed, plausible, tracked

        init?(heading: String) {
            let name = heading.dropFirst(3).uppercased()
            if name.hasPrefix("CONFIRMED") {
                self = .confirmed
            } else if name.hasPrefix("PLAUSIBLE") {
                self = .plausible
            } else if name.hasPrefix("ALREADY TRACKED") {
                self = .tracked
            } else {
                return nil
            }
        }

        var category: FindingCategory {
            switch self {
            case .confirmed: return .new
            case .plausible: return .needsDecision
            case .tracked: return .knownNewEvidence
            }
        }

        var verificationLabel: String {
            switch self {
            case .confirmed: return "Code-inspected · confirmed by review"
            case .plausible: return "Unconfirmed observation"
            case .tracked: return "Already tracked"
            }
        }

        var idLetter: String {
            switch self {
            case .confirmed: return "C"
            case .plausible: return "P"
            case .tracked: return "T"
            }
        }

        /// The ARCHITECTURE section's own verdicts: "**Drift — CONFIRMED (both checkers)**" and its
        /// PLAUSIBLE twin. They are findings with a move attached, and they were invisible because they
        /// sit under a bold line rather than a `##` heading.
        init?(driftHeading line: String) {
            let text = line.trimmingCharacters(in: .whitespaces).uppercased()
            guard text.hasPrefix("**"), text.contains("DRIFT") else { return nil }
            if text.contains("CONFIRMED") {
                self = .confirmed
            } else if text.contains("PLAUSIBLE") {
                self = .plausible
            } else {
                return nil
            }
        }
    }

    static func parse(_ markdown: String, runID: String) -> [Finding] {
        var findings: [Finding] = []
        var counts: [Section: Int] = [:]
        var section: Section?
        var bullet: String?
        var continuation: [String] = []

        func flush() {
            guard let section, let text = bullet else { return }
            let index = (counts[section] ?? 0) + 1
            counts[section] = index
            findings.append(finding(text, continuation: continuation, section: section, index: index, runID: runID))
            bullet = nil
            continuation = []
        }

        /// Inside ARCHITECTURE a bold line decides what follows: its drift lists are findings, its prose
        /// and its "missed by the surveyor" note are not. Elsewhere a bold line is ordinary text.
        var inArchitecture = false

        for line in GitOutput.lines(markdown) {
            if line.hasPrefix("#") {
                flush()
                let heading = line.hasPrefix("## ") ? line : nil
                inArchitecture = heading?.dropFirst(3).uppercased().hasPrefix("ARCHITECTURE") ?? false
                section = heading.flatMap(Section.init(heading:))
            } else if inArchitecture, line.trimmingCharacters(in: .whitespaces).hasPrefix("**") {
                flush()
                section = Section(driftHeading: line)
            } else if section != nil, let item = item(line) {
                flush()
                bullet = item
            } else if bullet != nil, line.first == " " || line.first == "\t" {
                continuation.append(line)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            }
        }
        flush()
        return findings
    }

    /// A finding's own line, whatever list marker the surveyor reached for: "- ", "* ", or "1. ".
    private static func item(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        guard let match = line.prefixMatch(of: numbered) else { return nil }
        return String(line[match.range.upperBound...])
    }

    private static func finding(_ text: String, continuation: [String], section: Section, index: Int, runID: String) -> Finding {
        // A bullet's claim is its first line; the mechanism, what was expected and what was measured are on
        // the indented lines under it. Reading only the first line gave every finding a title and an empty
        // body — a report of fifteen that said nothing once you opened one.
        let structured = ["touches:", "blocks:", "conflicts:"]
        let body = continuation.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in !structured.contains { line.hasPrefix($0) } }   // structured fields, not prose
        let parts = ([text] + body).joined(separator: " ")
            .components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        var locations: [String] = []
        var rest: [String] = []
        for part in parts.dropFirst() {
            // A part can hold several locations and then keep talking — "`A.swift:68` (fetch), `:17`
            // (comment)", or a whole paragraph after the file. Taking the part whole made the card's
            // location a three-line essay; taking only what matches leaves the prose where prose belongs.
            var remainder = Substring(part)
            var found = false
            while true {
                remainder = remainder.drop { "`,;·".contains($0) || $0.isWhitespace }
                guard let match = remainder.prefixMatch(of: location) else { break }
                let place = String(remainder[match.range])
                if !locations.contains(place) { locations.append(place) }
                remainder = remainder[match.range.upperBound...]
                found = true
            }
            let tail = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "`,;. ")).trimmingCharacters(in: .whitespaces)
            if !found { rest.append(part) } else if !tail.isEmpty { rest.append(tail) }
        }
        for path in continuation.flatMap(touchedPaths) where !locations.contains(path) {
            locations.append(path)
        }
        // A drift item is one sentence — "arch-1: dead copy at `View.swift:104-115` → delete it" — with no
        // " · " to split on, so its file:line sits inside the prose. Without this it had no location at all.
        if locations.isEmpty {
            for word in ([text] + body).joined(separator: " ").split(whereSeparator: \.isWhitespace) {
                let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "`.,;()"))
                if bare.prefixMatch(of: location) != nil, !locations.contains(bare) { locations.append(bare) }
            }
        }
        return Finding(id: "\(runID)-\(section.idLetter)\(index)", runID: runID, title: Markdown.plain(parts.first ?? text),
                       listDetail: section.category.rawValue, categories: [section.category],
                       // Markers off first, then escape what is left: the body is read, not rendered, so a
                       // paragraph of `backticks` and \*stars\* is punctuation nobody asked for — and escaping
                       // alone left the markers AND added backslashes. Escaping still runs, so a link in a
                       // report's own text stays literal text.
                       summary: Markdown.escape(Markdown.plain(rest.joined(separator: " · "))),
                       verificationLabel: section.verificationLabel, locations: locations, limits: limits)
    }

    /// The paths after "touches:" on a bullet's continuation line, up to whatever structured field follows —
    /// "blocks:" or "conflicts:". Stopping only at "blocks:" swallowed a conflicts list as if it were paths.
    private static func touchedPaths(_ line: String) -> [String] {
        guard let start = line.range(of: "touches:") else { return [] }
        var value = line[start.upperBound...]
        for field in ["blocks:", "conflicts:"] {
            if let next = value.range(of: field) { value = value[..<next.lowerBound] }
        }
        return value.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            .filter { !$0.isEmpty }
    }
}
