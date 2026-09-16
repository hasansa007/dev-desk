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
        /// Inside ARCHITECTURE a bold line decides what follows: its drift lists are findings, its prose
        /// and its "missed by the surveyor" note are not. Elsewhere a bold line is ordinary text.
        ///
        /// It is also the only thing that knows a drift from a defect once a bullet is flushed, so it is
        /// declared above `flush` rather than below it — a nested function cannot read what comes after it.
        var inArchitecture = false

        func flush() {
            guard let section, let text = bullet else { return }
            let index = (counts[section] ?? 0) + 1
            counts[section] = index
            findings.append(finding(text, continuation: continuation, section: section, index: index, runID: runID,
                                    kind: inArchitecture ? .architecture : .defect))
            bullet = nil
            continuation = []
        }

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

    /// `kind` comes from the section the bullet was read under, because nothing in the bullet itself says
    /// whether it is a defect or a drift — only where the report put it does.
    private static func finding(_ text: String, continuation: [String], section: Section, index: Int, runID: String,
                                kind: FindingKind) -> Finding {
        // A bullet's claim is its first line; the mechanism, what was expected and what was measured are on
        // the indented lines under it. Reading only the first line gave every finding a title and an empty
        // body — a report of fifteen that said nothing once you opened one.
        let body = continuation.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !isFieldLine($0) }   // structured fields, not prose
        let coordination = self.coordination(continuation)
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
        let touchedFiles = coordination.touches.isEmpty
            ? continuation.flatMap(touchedPaths) : coordination.touches.map(\.file)
        for path in touchedFiles where !locations.contains(path) {
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
        // The report's own id when it writes one: `needs`, `shares` and GROUPS refer to it, and it survives an
        // entry being moved within the report where a position would not.
        let id = coordination.ref.map { "\(runID)-\($0)" } ?? "\(runID)-\(section.idLetter)\(index)"
        return Finding(id: id, runID: runID, title: Markdown.plain(parts.first ?? text),
                       listDetail: section.category.rawValue, categories: [section.category],
                       // Markers off first, then escape what is left: the body is read, not rendered, so a
                       // paragraph of `backticks` and \*stars\* is punctuation nobody asked for — and escaping
                       // alone left the markers AND added backslashes. Escaping still runs, so a link in a
                       // report's own text stays literal text.
                       summary: Markdown.escape(Markdown.plain(rest.joined(separator: " · "))),
                       verificationLabel: section.verificationLabel, locations: locations, limits: limits,
                       kind: kind, coordination: coordination)
    }

    // MARK: - Coordination fields (ADR 0040)

    static let fieldKeys = ["id", "type", "group", "touches", "needs", "shares", "cases", "held", "near", "blocks", "conflicts"]
    /// Three or more spaces separate fields written on one line: `id: C1   type: Logic   group: G1 · 2 of 3`.
    private static let fieldGap = try! Regex(#"\s{3,}"#)

    static func isFieldLine(_ line: String) -> Bool {
        fields(in: line) != nil
    }

    /// `[(key, value)]` when the whole line is fields, nil when it is prose that merely contains a colon.
    static func fields(in line: String) -> [(String, String)]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var result: [(String, String)] = []
        for segment in trimmed.split(separator: fieldGap) {
            guard let colon = segment.firstIndex(of: ":") else {
                // A value with a wide gap inside it belongs to the field before it.
                guard let last = result.popLast() else { return nil }
                result.append((last.0, last.1 + " " + segment.trimmingCharacters(in: .whitespaces)))
                continue
            }
            let key = segment[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segment[segment.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if fieldKeys.contains(key) {
                result.append((key, value))
            } else if let last = result.popLast() {
                result.append((last.0, last.1 + "   " + segment))
            } else {
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    static func coordination(_ continuation: [String]) -> SurveyCoordination {
        var coordination = SurveyCoordination()
        for line in continuation {
            for (key, raw) in fields(in: line) ?? [] {
                let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                guard !value.isEmpty else { continue }
                switch key {
                case "id": coordination.ref = firstToken(value)
                case "type": coordination.type = TicketType(label: value)
                case "group":
                    guard value.lowercased() != "none" else { continue }
                    let parts = value.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
                    coordination.groupRef = parts.first.flatMap(firstToken)
                    if parts.count > 1 {
                        let numbers = parts[1].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                        coordination.groupOrder = numbers.first
                        coordination.groupSize = numbers.count > 1 ? numbers[1] : nil
                    }
                case "touches": coordination.touches += touches(value)
                case "needs": coordination.needs += link(value, waits: true).map { [$0] } ?? []
                case "shares":
                    let waits = value.lowercased().contains("same code")
                    coordination.shares += link(value, waits: waits).map { [$0] } ?? []
                case "cases":
                    coordination.cases += value.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                case "held": coordination.held.append(value)
                case "near": coordination.near = firstToken(value)
                default: break
                }
            }
        }
        return coordination
    }

    /// `A.swift › load(), request(); B.swift › View` — or the older bare `A.swift, B.swift`.
    static func touches(_ value: String) -> [CodeTouch] {
        guard value.contains("›") else {
            return value.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
                .filter { FindingGroups.isFileName(($0 as NSString).lastPathComponent) }
                .map { CodeTouch(file: $0, code: nil) }
        }
        return value.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: "›", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "` ")) }
            guard let file = pieces.first, !file.isEmpty else { return nil }
            return CodeTouch(file: file, code: pieces.count > 1 && !pieces[1].isEmpty ? pieces[1] : nil)
        }
    }

    /// `C2 — why` → (C2, why). The ref is the first word; what follows a dash is the note.
    static func link(_ value: String, waits: Bool) -> TicketLink? {
        guard let ref = firstToken(value) else { return nil }
        var note = String(value.dropFirst(value.distance(from: value.startIndex, to: value.range(of: ref)!.upperBound)))
            .trimmingCharacters(in: .whitespaces)
        if note.hasPrefix("—") || note.hasPrefix("-") { note = String(note.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return TicketLink(ref: ref, note: note, waits: waits)
    }

    static func firstToken(_ value: String) -> String? {
        value.split(whereSeparator: \.isWhitespace).first
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`#*,.;:()")) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The `## GROUPS` section: `### G1 · outcome`, a `branch: … · why: …` line, then its tickets in order.
    static func groups(_ markdown: String, runID: String) -> [SurveyGroup] {
        var groups: [SurveyGroup] = []
        var inGroups = false
        for line in GitOutput.lines(markdown) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inGroups = line.dropFirst(3).uppercased().hasPrefix("GROUPS")
                continue
            }
            guard inGroups else { continue }
            if line.hasPrefix("### ") {
                let heading = line.dropFirst(4)
                let parts = heading.components(separatedBy: " · ")
                guard let ref = parts.first.flatMap(firstToken) else { continue }
                let title = parts.dropFirst().joined(separator: " · ").trimmingCharacters(in: .whitespaces)
                groups.append(SurveyGroup(ref: ref, runID: runID, title: Markdown.plain(title.isEmpty ? ref : title),
                                          branch: nil, why: nil, members: []))
            } else if !groups.isEmpty, trimmed.lowercased().hasPrefix("branch:") || trimmed.lowercased().hasPrefix("why:") {
                for part in trimmed.components(separatedBy: " · why:") .enumerated() {
                    if part.offset == 0 {
                        if trimmed.lowercased().hasPrefix("why:") {
                            groups[groups.count - 1].why = String(part.element.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                        } else {
                            groups[groups.count - 1].branch = firstToken(String(part.element.dropFirst(7)))
                        }
                    } else {
                        groups[groups.count - 1].why = part.element.trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if !groups.isEmpty, let item = item(line), let ref = firstToken(item) {
                groups[groups.count - 1].members.append(ref)
            }
        }
        return groups
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
