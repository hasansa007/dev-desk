import Foundation

/// What a findings or ideation run does at a stop it would otherwise ask at (ADR 0043).
public enum StopChoice: String, CaseIterable, Hashable {
    case decide, alert, skip

    public var title: String {
        switch self {
        case .decide: return "Decide for me"
        case .alert: return "Alert me"
        case .skip: return "Skip"
        }
    }
}

/// The three stops and the agent limit, chosen before a run starts, so a run nobody is watching never waits
/// for an answer it asked nobody for.
public struct RunStops: Equatable, Hashable {
    /// Approving the fan-out. Never `skip`: a run has to plan.
    public var plan: StopChoice
    public var walkthrough: StopChoice
    public var filing: StopChoice
    public var maxAgents: Int

    public static let defaultMaxAgents = 40
    public static let maxAgentsRange = 5...300

    public init(plan: StopChoice = .decide, walkthrough: StopChoice = .skip, filing: StopChoice = .skip,
                maxAgents: Int = defaultMaxAgents) {
        self.plan = plan == .skip ? .decide : plan
        self.walkthrough = walkthrough
        self.filing = filing
        self.maxAgents = min(max(maxAgents, Self.maxAgentsRange.lowerBound), Self.maxAgentsRange.upperBound)
    }

    /// The door's own arguments, in the form its Phase 1 table reads.
    public var arguments: [String] {
        ["--plan=\(plan.rawValue)", "--walkthrough=\(walkthrough.rawValue)", "--file=\(filing.rawValue)",
         "--max-agents=\(maxAgents)"]
    }

    /// Stored as `decide,skip,skip`: the three choices, without the limit, which is app-wide.
    public var stored: String { [plan, walkthrough, filing].map(\.rawValue).joined(separator: ",") }

    public init(stored: String, maxAgents: Int) {
        let parts = stored.split(separator: ",").map { StopChoice(rawValue: String($0)) }
        let defaults = RunStops()
        self.init(plan: parts.count > 0 ? parts[0] ?? defaults.plan : defaults.plan,
                  walkthrough: parts.count > 1 ? parts[1] ?? defaults.walkthrough : defaults.walkthrough,
                  filing: parts.count > 2 ? parts[2] ?? defaults.filing : defaults.filing,
                  maxAgents: maxAgents)
    }

    /// The line a door ends with when its plan is over the limit. A run whose result starts with it failed.
    public static let refusalPrefix = "Refused:"

    public static func isRefusal(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(refusalPrefix) }
    }
}
