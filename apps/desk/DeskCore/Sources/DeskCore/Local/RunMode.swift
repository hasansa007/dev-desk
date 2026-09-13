import Foundation

/// How an agent works through a door once it is started. The door is the same either way; the mode decides
/// whether the agent does every step itself or hands the steps out and reviews what comes back. It is a
/// preference, not a per-run choice, because it says how a developer wants their tokens spent across a
/// project rather than what one run is about.
public enum RunMode: String, CaseIterable, Hashable {
    case standard, delegate

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .delegate: return "Delegate"
        }
    }

    public var detail: String {
        switch self {
        case .standard:
            return "The agent does the work itself, one step after another."
        case .delegate:
            return "The agent hands implementation to its own workers and reviews what comes back before accepting it."
        }
    }
}
