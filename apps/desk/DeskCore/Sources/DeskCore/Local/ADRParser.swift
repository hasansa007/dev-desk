import Foundation

/// Reads an ADR in this family's format (docs/adr/0002-diagrams-land-in-the-repo.md) as an answered decision.
enum ADRParser {
    static let rationaleLimit = 600

    private static let numberAndDash = try! Regex(#"^\d+\s*[—–:-]?\s*"#)

    static func parse(_ markdown: String, fileName: String) -> Decision {
        let stem = fileName.hasSuffix(".md") ? String(fileName.dropLast(3)) : fileName
        let number = String(stem.prefix { $0.isASCII && $0.isNumber })
        let lines = GitOutput.lines(markdown)
        let title = lines.first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2).trimmingPrefix(numberAndDash)).trimmingCharacters(in: .whitespaces) } ?? stem
        let status = value(of: "Status:", in: lines)
        let date = value(of: "Date:", in: lines)
        let meta = [number.isEmpty ? "ADR" : "ADR \(number)", status, date].filter { !$0.isEmpty }.joined(separator: " · ")
        let answer = DecisionAnswer(optionTitle: nil, rationale: Markdown.escape(rationale(lines)),
                                    answeredLabel: [status, date].filter { !$0.isEmpty }.joined(separator: " "))
        // The file name is repo-controlled; escape it and drop the backticks the escaper can't make safe inside a code span.
        return Decision(id: stem, listTitle: title, listMeta: meta, state: .answered, question: title,
                        context: "Recorded in \(Markdown.escape("docs/adr/\(fileName)"))", answer: answer, body: markdown)
    }

    private static func value(of key: String, in lines: [String]) -> String {
        lines.first { $0.hasPrefix(key) }.map { $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// The `## Decision` section with whitespace collapsed, ending in "…" when cut at the limit.
    private static func rationale(_ lines: [String]) -> String {
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Decision" }) else { return "" }
        let section = lines[(start + 1)...].prefix { !$0.hasPrefix("## ") }
        let collapsed = section.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > rationaleLimit else { return collapsed }
        return String(collapsed.prefix(rationaleLimit - 1)) + "…"
    }
}
