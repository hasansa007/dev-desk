import Foundation

/// An agent the developer added for Sessions: a name, and the line typed into a login shell at the project root.
/// Not a "Start with" entry — those carry a task's `{prompt}`, and a bare session has no task to fill it from.
public struct CustomSessionAgent: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var command: String

    public init(id: String = UUID().uuidString, name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

/// What Sessions' picker offers, as Settings › Agents and defaults stores it: which of the built-in agents are
/// listed, and the developer's own. Both stored for every project.
public enum SessionAgents {
    /// Claude and Codex, the two the picker offered before it was configurable.
    public static let defaultBuiltIns = "claude,codex"

    /// The listed built-ins, in `AgentKind`'s order whatever order they were stored in. An unknown name — a
    /// hand-edited default, an agent since removed — is dropped rather than failing the whole list.
    public static func builtIns(_ stored: String) -> [AgentKind] {
        let names = Set(stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return AgentKind.allCases.filter { names.contains($0.rawValue) }
    }

    public static func store(_ agents: [AgentKind]) -> String {
        AgentKind.allCases.filter(agents.contains).map(\.rawValue).joined(separator: ",")
    }

    /// An unreadable value is an empty list, not a crash — a hand-edited default must not take Settings down with it.
    public static func decodeCustom(_ data: Data) -> [CustomSessionAgent] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([CustomSessionAgent].self, from: data)) ?? []
    }

    public static func encodeCustom(_ agents: [CustomSessionAgent]) -> Data {
        (try? JSONEncoder().encode(agents)) ?? Data()
    }
}
