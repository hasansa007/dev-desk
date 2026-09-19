import Foundation

/// One flow the Sequence list offers to draw (ADR 0047): a thing a user or a job does, end to end.
public struct SequenceFlow: Identifiable, Hashable {
    /// Where the flow was named. Every source counts the same; a flow two sources name is listed once.
    public enum Source: String, Hashable, CaseIterable, Comparable {
        case architecture = "Architecture", dataflow = "Data flow", hunt = "Findings hunt", drawn = "Drawn earlier",
             catalog = "Flow list"
        public static func < (a: Source, b: Source) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    public var name: String
    public var slug: String
    public var sources: Set<Source>
    public var drawing: ArchDiagram?
    public var id: String { slug }

    public init(name: String, slug: String, sources: Set<Source>, drawing: ArchDiagram? = nil) {
        self.name = name
        self.slug = slug
        self.sources = sources
        self.drawing = drawing
    }

    /// The key a flow's generate is tracked under, beside the plain kinds.
    public var generateKey: String { SequenceFlows.key(slug) }
}

public enum SequenceFlows {
    static let keyPrefix = "sequence:"

    /// "sequence:<slug>" — how a flow's run is keyed among the kinds' runs.
    public static func key(_ slug: String) -> String { keyPrefix + slug }
    public static func slug(fromKey key: String) -> String? {
        key.hasPrefix(keyPrefix) ? String(key.dropFirst(keyPrefix.count)) : nil
    }

    /// "Build a course" → "build-a-course": lowercased, letters and digits kept, anything else one dash.
    public static func slug(_ name: String) -> String {
        var out = ""
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { out.unicodeScalars.append(scalar) }
            else if !out.isEmpty, !out.hasSuffix("-") { out.append("-") }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// Every flow the project has named, whichever source is ready: the named views of the newest Architecture
    /// and Data flow drawings, and the flows the newest findings hunt read. None is required. A sequence drawn
    /// for a flow no source names any more stays listed, as Drawn earlier, so a drawing never goes missing.
    ///
    /// `catalog` is the project's own flow list (`docs/flows.md`): each flow once, with the other names sources
    /// give it. Those names fold into its row, so "Build path", "Build a course" and "build-create" are one flow.
    public static func list(diagrams: [ArchDiagram], huntFlows: [String],
                            catalog: [FlowCatalogEntry] = []) -> [SequenceFlow] {
        var flows: [String: SequenceFlow] = [:]
        var order: [String] = []
        var canonical: [String: String] = [:]
        for entry in catalog {
            let key = slug(entry.name)
            guard !key.isEmpty, flows[key] == nil else { continue }
            flows[key] = SequenceFlow(name: entry.name, slug: key, sources: [])
            order.append(key)
            for alias in entry.aliases { canonical[slug(alias)] = key }
        }
        func resolve(_ raw: String) -> String { canonical[raw] ?? raw }
        func add(_ name: String, _ source: SequenceFlow.Source) {
            let slug = resolve(slug(name))
            guard !slug.isEmpty else { return }
            if flows[slug] == nil {
                flows[slug] = SequenceFlow(name: name, slug: slug, sources: [])
                order.append(slug)
            }
            flows[slug]?.sources.insert(source)
        }
        for kind in ["architecture", "dataflow"] {
            let newest = diagrams.filter { $0.kind == kind }.max { $0.modifiedAt < $1.modifiedAt }
            for view in newest?.views ?? [] { add(view, kind == "architecture" ? .architecture : .dataflow) }
        }
        for flow in huntFlows { add(ArchDiagrams.readableName(flow), .hunt) }
        let sequences = diagrams.filter { $0.kind == "sequence" }.sorted { $0.modifiedAt > $1.modifiedAt }
        for sequence in sequences {
            let slug = resolve(sequence.flowSlug ?? slug(sequence.title))
            if flows[slug] == nil {
                flows[slug] = SequenceFlow(name: sequence.title, slug: slug, sources: [.drawn])
                order.append(slug)
            }
            if flows[slug]?.drawing == nil { flows[slug]?.drawing = sequence }
        }
        // A listed flow no source has named yet still says where it came from.
        for key in order where flows[key]?.sources.isEmpty == true { flows[key]?.sources.insert(.catalog) }
        return order.compactMap { flows[$0] }
    }

    public static let catalogPath = "docs/flows.md"

    /// `docs/flows.md`: one bullet per flow — `- Build a course — also: Build path, build-create` — and nothing
    /// else is read. The name is how every screen and door calls the flow; `also:` lists what other sources call it.
    public static func catalog(in markdown: String) -> [FlowCatalogEntry] {
        markdown.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
            let body = String(trimmed.dropFirst(2))
            let parts = body.components(separatedBy: "also:")
            let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " —–-:·"))
            guard !name.isEmpty else { return nil }
            let aliases = parts.count > 1
                ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            return FlowCatalogEntry(name: name, aliases: aliases)
        }
    }

    public static func catalog(repositoryRoot: String) -> [FlowCatalogEntry] {
        let root = URL(fileURLWithPath: repositoryRoot, isDirectory: true)
        guard case .text(let text) = SafeFile.read(root.appendingPathComponent(catalogPath), maxBytes: 262_144, within: root)
        else { return [] }
        return catalog(in: text)
    }

    /// The flows a findings report says its hunt read: the ids in its "Per flow" table (`dev:findings` Phase 7),
    /// one per line, two-space indented, name then a gap then counts. Anything else in the report is ignored.
    public static func huntFlows(in markdown: String) -> [String] {
        var flows: [String] = []
        var inTable = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("Per flow") { inTable = true; continue }
            guard inTable else { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { if !flows.isEmpty { break } else { continue } }
            guard line.hasPrefix("  "),
                  let match = line.range(of: #"^\s+([a-z0-9][a-z0-9-]*)\s{2,}"#, options: .regularExpression) else { continue }
            flows.append(line[match].trimmingCharacters(in: .whitespaces))
        }
        return flows
    }

    /// The newest findings report in a repository (`docs/findings/`, then the older `docs/survey/`), read for its flows.
    public static func huntFlows(repositoryRoot: String) -> [String] {
        let root = URL(fileURLWithPath: repositoryRoot, isDirectory: true)
        for folder in ["docs/findings", "docs/survey"] {
            let dir = root.appendingPathComponent(folder)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".md") }.sorted()
            guard let newest = names.last,
                  case .text(let text) = SafeFile.read(dir.appendingPathComponent(newest), maxBytes: 1_048_576, within: dir)
            else { continue }
            return huntFlows(in: text)
        }
        return []
    }
}

/// One line of `docs/flows.md`: a flow's name, and what else it is called.
public struct FlowCatalogEntry: Hashable {
    public var name: String
    public var aliases: [String]
    public init(name: String, aliases: [String] = []) {
        self.name = name
        self.aliases = aliases
    }
}
