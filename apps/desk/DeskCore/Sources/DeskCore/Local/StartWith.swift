import Foundation

/// One entry in the developer's own "Start with" list: another app that can take a task (ADR 0036 decision 6,
/// *Continue in ▾*, widened from a fixed set to a list the developer keeps).
///
/// Two kinds, because apps accept different things. An `app` is opened on the project folder, which nearly every
/// app accepts and which carries no task. A `command` is typed into Dev Desk's built-in terminal with the task
/// filled in, which reaches any app that ships a command line without Dev Desk having to know that app.
public struct StartWithEntry: Codable, Identifiable, Hashable {
    public enum Kind: Codable, Hashable {
        /// A `.app` bundle's path, opened on the project folder.
        case app(path: String)
        /// A shell line with `{placeholders}`; see `StartWithTemplate`.
        case command(template: String)
    }

    public let id: String
    public var name: String
    public var kind: Kind

    public init(id: String = UUID().uuidString, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// The short note a start-sheet row carries.
    public var detail: String {
        switch kind {
        case .app: return "opens the folder"
        case .command: return "command"
        }
    }
}

/// Filling a command's placeholders. Every value is single-quoted as it goes in, so a card title carrying a quote
/// or a `;` cannot end the string or start a second command — which also means a template must NOT quote a
/// placeholder itself: `--prompt {prompt}`, never `--prompt "{prompt}"`.
public enum StartWithTemplate {
    public static let placeholders = ["folder", "prompt", "taskFile", "title"]

    /// The line to type, and any `{name}` the template uses that is not a placeholder — left in the line as
    /// written, and reported, so Settings can say so rather than the terminal failing on it.
    public static func render(_ template: String, values: [String: String]) -> (line: String, unknown: [String]) {
        var line = "", unknown: [String] = [], rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            line += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            if let value = values[name] {
                line += DoorCommand.quoted(value)
            } else {
                line += rest[open...close]
                // Only something shaped like a placeholder is reported: awk's `{print}` is not a mistake.
                if StartWithTemplate.looksLikePlaceholder(name), !unknown.contains(name) { unknown.append(name) }
            }
            rest = rest[rest.index(after: close)...]
        }
        return (line + rest, unknown)
    }

    /// What Settings warns about before a command is ever run.
    public static func unknownPlaceholders(in template: String) -> [String] {
        render(template, values: Dictionary(uniqueKeysWithValues: placeholders.map { ($0, "") })).unknown
    }

    static func looksLikePlaceholder(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// The list as it is stored: JSON under one preference key, for every project. An unreadable value is an empty
/// list, not a crash — a hand-edited default must not take Settings down with it.
public enum StartWithList {
    public static func decode(_ data: Data) -> [StartWithEntry] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([StartWithEntry].self, from: data)) ?? []
    }

    public static func encode(_ entries: [StartWithEntry]) -> Data {
        (try? JSONEncoder().encode(entries)) ?? Data()
    }
}
