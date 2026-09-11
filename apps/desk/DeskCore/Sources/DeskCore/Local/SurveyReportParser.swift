import Foundation

/// Reads a dev:survey report (skills/survey/SKILL.md): CONFIRMED, PLAUSIBLE and ALREADY TRACKED bullets become findings.
enum SurveyReportParser {
    static let limits = "Survey checks code only; nothing here was reproduced in a running app."

    private static let location = try! Regex(#"^[^\s·]+:\d+"#)

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
        return findings
    }

    private static func finding(_ text: String, continuation: [String], section: Section, index: Int, runID: String) -> Finding {
        let parts = text.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        var locations: [String] = []
        var rest: [String] = []
        for part in parts.dropFirst() {
            let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if bare.prefixMatch(of: location) != nil { locations.append(bare) } else { rest.append(part) }
        }
        for path in continuation.flatMap(touchedPaths) where !locations.contains(path) {
            locations.append(path)
        }
        return Finding(id: "\(runID)-\(section.idLetter)\(index)", runID: runID, title: parts.first ?? text,
                       listDetail: section.category.rawValue, categories: [section.category],
                       summary: Markdown.escape(rest.joined(separator: " · ")),
                       verificationLabel: section.verificationLabel, locations: locations, limits: limits)
    }

    /// The paths after "touches:" on a bullet's continuation line, up to a "blocks:" field.
    private static func touchedPaths(_ line: String) -> [String] {
        guard let start = line.range(of: "touches:") else { return [] }
        var value = line[start.upperBound...]
        if let blocks = value.range(of: "blocks:") { value = value[..<blocks.lowerBound] }
        return value.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            .filter { !$0.isEmpty }
    }
}
