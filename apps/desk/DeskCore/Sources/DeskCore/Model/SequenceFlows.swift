import Foundation

/// One flow the Sequence list offers to draw (ADR 0047): a thing a user or a job does, end to end.
public struct SequenceFlow: Identifiable, Hashable {
    /// Where the flow was named. Every source counts the same; a flow two sources name is listed once.
    public enum Source: String, Hashable, CaseIterable, Comparable {
        case architecture = "Architecture", dataflow = "Data flow", hunt = "Findings hunt", drawn = "Drawn earlier"
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
    public static func list(diagrams: [ArchDiagram], huntFlows: [String]) -> [SequenceFlow] {
        var flows: [String: SequenceFlow] = [:]
        var order: [String] = []
        func add(_ name: String, _ source: SequenceFlow.Source) {
            let slug = slug(name)
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
            let slug = sequence.flowSlug ?? slug(sequence.title)
            if flows[slug] == nil {
                flows[slug] = SequenceFlow(name: sequence.title, slug: slug, sources: [.drawn])
                order.append(slug)
            }
            if flows[slug]?.drawing == nil { flows[slug]?.drawing = sequence }
        }
        return order.compactMap { flows[$0] }
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
