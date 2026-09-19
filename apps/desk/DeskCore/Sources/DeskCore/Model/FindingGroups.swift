import Foundation

/// How the findings list is sectioned: by what each finding asks of you, or by the file it points at.
public enum FindingGrouping: String, CaseIterable, Hashable {
    /// The tickets as they will run: each group in order, then what runs on its own, then what is held (ADR 0040).
    case group = "By group"
    case status = "By status"
    case file = "By file"
}

/// One section of the findings list. `lines` is only set when grouped by file: the parts of each finding's
/// locations that fall in this file, so a row can say `:101` under a header that already names the file.
public struct FindingGroup: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var category: FindingCategory?
    public var findings: [Finding]
    public var lines: [String: String]
    /// A group's branch and why it is a group — said once in its header.
    public var detail: String?

    public init(id: String, title: String, category: FindingCategory? = nil, findings: [Finding], lines: [String: String] = [:],
                detail: String? = nil) {
        self.detail = detail
        self.id = id
        self.title = title
        self.category = category
        self.findings = findings
        self.lines = lines
    }

    /// Said once in the header when every finding in the section says it, instead of on every row.
    public var sharedVerification: String? {
        let labels = Set(findings.map(\.verificationLabel))
        return labels.count == 1 ? labels.first : nil
    }
}

public enum FindingGroups {
    /// The order a finding's categories are read in: a finding carrying two is shown under the first.
    static let statusOrder: [FindingCategory] = [.new, .knownNewEvidence, .needsDecision, .closedOrDeclined]

    /// A section is titled by what it needs from you, not by the report's verdict word (ADR 0046): "New" named a
    /// state, where the developer's question is "what do I do with these?".
    public static func needTitle(_ category: FindingCategory) -> String {
        switch category {
        case .new: return "Needs your decision"
        case .needsDecision: return "Not verified yet"
        case .knownNewEvidence: return "Already tracked"
        case .closedOrDeclined: return "Closed or declined"
        }
    }

    public static func group(_ findings: [Finding], by grouping: FindingGrouping, filed: Set<String> = [],
                             groups: [FindingsGroup] = []) -> [FindingGroup] {
        switch grouping {
        case .group: return byGroup(findings, groups: groups, filed: filed)
        case .status: return byStatus(findings, filed: filed)
        case .file: return byFile(findings)
        }
    }

    /// Empty sections are left out, and a finding with no category lands last rather than disappearing.
    /// Findings already filed — ids in `filed` — leave their category for a Filed section at the end: "New ·
    /// not filed yet" over a finding that is on the board is a header saying something untrue.
    public static func byStatus(_ findings: [Finding], filed: Set<String> = []) -> [FindingGroup] {
        let open = findings.filter { !filed.contains($0.id) }
        var groups = statusOrder.map { category in
            FindingGroup(id: category.rawValue, title: needTitle(category), category: category,
                         findings: open.filter { primary($0) == category })
        }
        let rest = open.filter { primary($0) == nil }
        if !rest.isEmpty { groups.append(FindingGroup(id: "uncategorised", title: "Uncategorised", findings: rest)) }
        // A merge is not a new issue: it gets its own section so "Filed" counts only what added a number (ADR 0046).
        let done = findings.filter { filed.contains($0.id) }
        let merged = done.filter { if case .merged = $0.filing { return true } else { return false } }
        groups.append(FindingGroup(id: "filed", title: "Filed", findings: done.filter { !merged.contains($0) }))
        groups.append(FindingGroup(id: "merged", title: "Added to an open issue", findings: merged))
        return groups.filter { !$0.findings.isEmpty }
    }

    /// Each report group in its own order, then the tickets that run on their own, then held findings. A report
    /// with no GROUPS section has nothing to group by, so it reads by status instead.
    public static func byGroup(_ findings: [Finding], groups: [FindingsGroup], filed: Set<String> = []) -> [FindingGroup] {
        let runs = Set(findings.map(\.runID))
        let relevant = groups.filter { runs.contains($0.runID) }
        guard !relevant.isEmpty else { return byStatus(findings, filed: filed) }
        var placed: Set<String> = []
        var sections: [FindingGroup] = []
        for group in relevant {
            let mine = findings.filter { $0.runID == group.runID }
            var members = group.members.compactMap { ref in mine.first { $0.coordination.ref == ref } }
            // A ticket that names this group but was left off its list still belongs to it, after the listed ones.
            members += mine.filter { $0.coordination.groupRef == group.ref && !members.contains($0) }
                .sorted { ($0.coordination.groupOrder ?? .max) < ($1.coordination.groupOrder ?? .max) }
            members = members.filter { !placed.contains($0.id) }
            guard !members.isEmpty else { continue }
            placed.formUnion(members.map(\.id))
            let detail = [group.branch, group.why].compactMap { $0 }.joined(separator: " · ")
            sections.append(FindingGroup(id: "group-\(group.id)", title: group.title, findings: members,
                                         detail: detail.isEmpty ? nil : detail))
        }
        let rest = findings.filter { !placed.contains($0.id) }
        let held = rest.filter { $0.categories.contains(.needsDecision) && !filed.contains($0.id) }
        let own = rest.filter { !held.contains($0) }
        if !own.isEmpty {
            sections.append(FindingGroup(id: "ungrouped", title: "On its own", findings: own,
                                         detail: "its own branch · waits only for the code it shares"))
        }
        if !held.isEmpty {
            sections.append(FindingGroup(id: "held", title: "Held", category: .needsDecision, findings: held))
        }
        return sections
    }

    /// Busiest file first. A finding spanning three files is listed under all three — that is what "which
    /// file is worst" is asking — and one with no location gets a section of its own at the end.
    ///
    /// A report names one file both ways — `Views/List.swift:100` where it cites a line, `List.swift` where it
    /// only mentions it — so sections are keyed by file name and titled with the longest path seen for it.
    public static func byFile(_ findings: [Finding]) -> [FindingGroup] {
        var order: [String] = []
        var members: [String: [Finding]] = [:]
        var lines: [String: [String: String]] = [:]
        var titles: [String: String] = [:]
        var unlocated: [Finding] = []
        for finding in findings {
            let parts = finding.locations.map(split)
            if parts.isEmpty { unlocated.append(finding); continue }
            for (path, line) in parts {
                let file = (path as NSString).lastPathComponent
                if path.count > titles[file, default: ""].count { titles[file] = path }
                if members[file] == nil { order.append(file); members[file] = [] }
                if !members[file]!.contains(where: { $0.id == finding.id }) { members[file]!.append(finding) }
                if let line {
                    let existing = lines[file, default: [:]][finding.id]
                    lines[file, default: [:]][finding.id] = existing.map { "\($0), \(line)" } ?? line
                }
            }
        }
        var groups = order.map { FindingGroup(id: $0, title: titles[$0] ?? $0, findings: members[$0]!, lines: lines[$0] ?? [:]) }
        // Stable: files with the same count keep the order the report first mentioned them in.
        groups = groups.enumerated().sorted {
            $0.element.findings.count != $1.element.findings.count
                ? $0.element.findings.count > $1.element.findings.count : $0.offset < $1.offset
        }.map(\.element)
        if !unlocated.isEmpty { groups.append(FindingGroup(id: "no-location", title: "No source location", findings: unlocated)) }
        return groups
    }

    /// The files a finding names, once each by file name, in the order the report cites them — the labels a row
    /// carries. Line ranges are left to the tooltip: a head-truncated `…re.swift:103` said where, not which file.
    public static func fileNames(_ locations: [String]) -> [String] {
        var files: [String] = []
        for location in locations {
            let file = (split(location).file as NSString).lastPathComponent
            if isFileName(file), !files.contains(file) { files.append(file) }
        }
        return files
    }

    /// `List.swift`, not `and whatever each seam needs`: a report's `touches:` line is prose split on commas, and
    /// a word from it is not a file to label.
    static func isFileName(_ name: String) -> Bool {
        guard !name.contains(where: \.isWhitespace), let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return name.index(after: dot) != name.endIndex
    }

    /// The locations of one file among a finding's, for that file's label tooltip.
    public static func locations(_ locations: [String], inFile name: String) -> [String] {
        locations.filter { (split($0).file as NSString).lastPathComponent == name }
    }

    static func primary(_ finding: Finding) -> FindingCategory? {
        statusOrder.first { finding.categories.contains($0) }
    }

    /// `Sources/App.swift:12-14` → (`Sources/App.swift`, `:12-14`). A location with no line is the whole file.
    static func split(_ location: String) -> (file: String, line: String?) {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.lastIndex(of: ":") else { return (trimmed, nil) }
        let suffix = trimmed[trimmed.index(after: colon)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "–" }) else { return (trimmed, nil) }
        return (String(trimmed[..<colon]), ":" + suffix)
    }
}
