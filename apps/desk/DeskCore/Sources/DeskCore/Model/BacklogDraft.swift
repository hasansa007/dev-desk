import Foundation

/// One item on its way to a backlog — whichever backlog this project has. The same draft becomes a file in
/// `docs/backlog/` when there is no tracker, and the description handed to `dev:create-issue` when there is
/// (ADR 0027), so what a card files does not depend on where it lands.
public struct BacklogDraft: Equatable {
    /// What it was filed from, so the card that filed it can tell it has been filed.
    public var key: String
    public var title: String
    /// Markdown for a person to read in the file. Plain text: nothing in it is escaped for the app's renderer.
    public var body: String
    /// One line, for the door's prompt.
    public var description: String
    public var area: String?
    public var source: String?

    public init(key: String, title: String, body: String, description: String, area: String? = nil, source: String? = nil) {
        self.key = key
        self.title = title
        self.body = body
        self.description = description
        self.area = area
        self.source = source
    }

    static func sections(_ parts: [(String, String?)]) -> String {
        parts.compactMap { heading, text in
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return "## \(heading)\n\n\(text)"
        }.joined(separator: "\n\n")
    }
}

extension Finding {
    public var backlogDraft: BacklogDraft {
        let sources = locations.isEmpty ? nil : locations.map { "- `\($0)`" }.joined(separator: "\n")
        let body = BacklogDraft.sections([
            ("What", Markdown.unescape(summary)),
            ("Sources", sources),
            ("Found by", "dev:survey, run \(runID) · \(Markdown.unescape(verificationLabel))"),
            ("Limits", Markdown.unescape(limits)),
        ])
        return BacklogDraft(key: id, title: Markdown.unescape(title), body: body, description: backlogDescription,
                            area: area?.rawValue, source: "dev:survey run \(runID)")
    }
}

extension Opportunity {
    public var backlogDraft: BacklogDraft {
        let title = Markdown.unescape(self.title)
        let sources = locations.isEmpty ? nil : locations.map { "- `\($0)`" }.joined(separator: "\n")
        let body = BacklogDraft.sections([
            ("Proposed", proposed.map(Markdown.unescape)),
            ("Why", Markdown.unescape(summary)),
            ("Gain", gain.map(Markdown.unescape)),
            ("Cost", cost.map(Markdown.unescape)),
            ("Doing nothing", doingNothing.map(Markdown.unescape)),
            ("Sources", sources),
            ("Found by", "dev:ideation, run \(runID)"),
            ("Limits", Markdown.unescape(limits)),
        ])
        let proposal = proposed.map { " Proposed: \(Markdown.unescape($0))." } ?? ""
        let sourceLine = locations.isEmpty ? "" : " Sources: \(locations.joined(separator: ", "))."
        let description = "\(title).\(proposal)\(sourceLine) Gain: \(gain.map(Markdown.unescape) ?? "not stated"). "
            + "Cost: \(cost.map(Markdown.unescape) ?? "not stated"). Doing nothing: \(doingNothing.map(Markdown.unescape) ?? "not stated"). "
            + "Found by dev:ideation, run \(runID). \(Markdown.unescape(limits))"
        return BacklogDraft(key: id, title: title, body: body, description: description,
                            area: FindingArea.of(paths: locations)?.rawValue, source: "dev:ideation run \(runID)")
    }
}
