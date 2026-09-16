import Foundation

/// How the survey list is sectioned: by what each finding asks of you, or by the file it points at.
public enum FindingGrouping: String, CaseIterable, Hashable {
    case status = "By status"
    case file = "By file"
}

/// One section of the survey list. `lines` is only set when grouped by file: the parts of each finding's
/// locations that fall in this file, so a row can say `:101` under a header that already names the file.
public struct FindingGroup: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var category: FindingCategory?
    public var findings: [Finding]
    public var lines: [String: String]

    public init(id: String, title: String, category: FindingCategory? = nil, findings: [Finding], lines: [String: String] = [:]) {
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

    public static func group(_ findings: [Finding], by grouping: FindingGrouping, filed: Set<String> = []) -> [FindingGroup] {
        switch grouping {
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
            FindingGroup(id: category.rawValue, title: category.rawValue, category: category,
                         findings: open.filter { primary($0) == category })
        }
        let rest = open.filter { primary($0) == nil }
        if !rest.isEmpty { groups.append(FindingGroup(id: "uncategorised", title: "Uncategorised", findings: rest)) }
        groups.append(FindingGroup(id: "filed", title: "Filed", findings: findings.filter { filed.contains($0.id) }))
        return groups.filter { !$0.findings.isEmpty }
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

    /// The files a finding names, by file name, for a column too narrow for paths: `List.swift +2`. Line ranges
    /// are left to the tooltip — a head-truncated `…re.swift:103` showed where in a file, not which file.
    public static func fileSummary(_ locations: [String]) -> String {
        var files: [String] = []
        for location in locations {
            let file = (split(location).file as NSString).lastPathComponent
            if !file.isEmpty, !files.contains(file) { files.append(file) }
        }
        guard let first = files.first else { return "—" }
        return files.count > 1 ? "\(first) +\(files.count - 1)" : first
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
