import Foundation

/// One row in the start sheet: something that can carry a `TaskLaunch`.
///
/// ADR 0036 decision 2 splits these by what they can promise, not by what is convenient. A `.here`
/// runner is a protocol session the app hosts and can hold a gate open on; a `.handoff` hands the
/// launch to a tool that runs it out of sight. There is deliberately no third kind for "run it here
/// but the gate arrives afterwards" — that was the capability fallback the review removed.
public struct RunnerOption: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        /// A protocol session, gateable, counted against the slot limit.
        case here
        /// Launched elsewhere: watched by its branch, never in a slot.
        case handoff
    }

    /// Stable across refreshes: the ACP registry's agent id, or the launcher's own (`terminal`, `vscode`).
    public let id: String
    public let name: String
    /// The short right-hand note a row carries: `acp v1`, `--from-file`, `not installed`.
    public let detail: String?
    public let kind: Kind
    /// A row that cannot be chosen is still shown, with `detail` saying why — absence is information.
    public let isAvailable: Bool

    public init(id: String, name: String, detail: String? = nil, kind: Kind, isAvailable: Bool = true) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
        self.isAvailable = isAvailable
    }
}

/// What the start sheet offers, as two lists that never blend.
///
/// `hereEmptyReason` is the honest-empty state decision 2 requires: with no ACP adapter found, *Run it
/// here* says why and the hand-offs are the answer. It is never filled by demoting a runner into a
/// weaker one.
public struct RunnerChoices: Hashable {
    public let here: [RunnerOption]
    public let handoff: [RunnerOption]
    public let hereEmptyReason: String?

    public init(here: [RunnerOption], handoff: [RunnerOption], hereEmptyReason: String? = nil) {
        self.here = here
        self.handoff = handoff
        self.hereEmptyReason = hereEmptyReason
    }

    /// The rows that can actually start something, which is what a default selection may come from.
    public var runnable: [RunnerOption] { (here + handoff).filter(\.isAvailable) }
}
