import Foundation

/// What kind of change a findings ticket asks for (ADR 0040). Kind says which half of the report a finding came
/// from; this says what fixing it touches, which is what decides its order inside a group.
public enum TicketType: String, CaseIterable, Hashable {
    case dataFlow = "Data flow"
    case logic = "Logic"
    case ui = "UI"
    case architecture = "Architecture"
    case tests = "Tests"

    init?(label: String) {
        let text = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == text }) else { return nil }
        self = match
    }
}

/// `ContactsStore.swift › load(), requestAccessIfNeeded()` — the file, and the code in it the fix changes.
public struct CodeTouch: Hashable {
    public var file: String
    public var code: String?
    public init(file: String, code: String?) {
        self.file = file
        self.code = code
    }
}

/// A `needs:` or `shares:` line: the ticket it names, what it says about it, and whether it means waiting.
public struct TicketLink: Hashable {
    public var ref: String
    public var note: String
    public var waits: Bool
    public init(ref: String, note: String, waits: Bool) {
        self.ref = ref
        self.note = note
        self.waits = waits
    }
}

/// The lines a grouped findings report writes under each ticket. All optional: a report written before
/// ADR 0040 has none of them, and reads exactly as it did.
public struct FindingsCoordination: Hashable {
    public var ref: String?
    public var type: TicketType?
    public var groupRef: String?
    public var groupOrder: Int?
    public var groupSize: Int?
    public var touches: [CodeTouch] = []
    public var needs: [TicketLink] = []
    public var shares: [TicketLink] = []
    public var cases: [String] = []
    public var held: [String] = []
    public var near: String?

    public init() {}

    public var isEmpty: Bool { self == FindingsCoordination() }

    /// The coordination as the `## Scope` lines a filed ticket carries, in the report's own words.
    public var scopeLines: [String] {
        var lines: [String] = []
        if let type { lines.append("type: \(type.rawValue)") }
        if let groupRef { lines.append("group: \(groupRef)" + (position.map { " · \($0)" } ?? "")) }
        if !touches.isEmpty {
            lines.append("touches: " + touches.map { touch in touch.code.map { "\(touch.file) › \($0)" } ?? touch.file }
                .joined(separator: "; "))
        }
        lines += needs.map { "needs: \($0.ref)" + ($0.note.isEmpty ? "" : " — \($0.note)") }
        lines += shares.map { "shares: \($0.ref)" + ($0.note.isEmpty ? "" : " \($0.note)") }
        if !cases.isEmpty { lines.append("cases: " + cases.joined(separator: " · ")) }
        lines += held.map { "held: \($0)" }
        return lines
    }

    /// Every ticket this one waits for: its `needs`, and the `shares` that touch the same code.
    public var waitsFor: [String] { (needs + shares.filter(\.waits)).map(\.ref) }

    /// `2 of 3`, when the report said where in its group this ticket goes.
    public var position: String? {
        guard let groupOrder else { return nil }
        return groupSize.map { "\(groupOrder) of \($0)" } ?? "\(groupOrder)"
    }
}

/// One `### G1 · outcome` block under `## GROUPS`: tickets that reach the base branch together (ADR 0040).
public struct FindingsGroup: Identifiable, Hashable {
    public var id: String { "\(runID)-\(ref)" }
    public var ref: String
    public var runID: String
    public var title: String
    public var branch: String?
    public var why: String?
    /// Ticket refs, in the order they run.
    public var members: [String]

    public init(ref: String, runID: String, title: String, branch: String?, why: String?, members: [String]) {
        self.ref = ref
        self.runID = runID
        self.title = title
        self.branch = branch
        self.why = why
        self.members = members
    }
}
