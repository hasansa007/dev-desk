/// What `dev:ideation` concluded about one opportunity. Refuted and declined have no survey equivalent:
/// a defect's existence argues for fixing it, an opportunity's does not.
public enum OpportunityVerdict: String, CaseIterable, Hashable {
    case confirmed = "Confirmed"
    case plausible = "Plausible"
    case refuted = "Refuted"
    case declined = "Declined before"
    case tracked = "Already tracked"
}

public struct IdeationRun: Identifiable, Hashable {
    public var id: String
    public var label: String
    /// "perf · security · quality", when the report's header names the kinds it covered.
    public var kinds: String?
    public init(id: String, label: String, kinds: String? = nil) {
        self.id = id
        self.label = label
        self.kinds = kinds
    }
}

public struct Opportunity: Identifiable, Hashable {
    public var id: String
    public var runID: String
    /// The measured or derived current behaviour, left of the report's arrow.
    public var title: String
    /// What the door proposes instead, right of the arrow; nil when the bullet states no change.
    public var proposed: String?
    public var gain: String?
    public var cost: String?
    /// What it costs to leave this alone — "nothing measurable" is an honest and common answer.
    public var doingNothing: String?
    public var summary: String
    public var verdict: OpportunityVerdict
    public var locations: [String]
    public var limits: String

    public init(id: String, runID: String, title: String, proposed: String? = nil, gain: String? = nil, cost: String? = nil,
                doingNothing: String? = nil, summary: String = "", verdict: OpportunityVerdict, locations: [String] = [],
                limits: String) {
        self.id = id
        self.runID = runID
        self.title = title
        self.proposed = proposed
        self.gain = gain
        self.cost = cost
        self.doingNothing = doingNothing
        self.summary = summary
        self.verdict = verdict
        self.locations = locations
        self.limits = limits
    }
}

public struct IdeationReport: Hashable {
    public var runs: [IdeationRun]
    public var opportunities: [Opportunity]
    public init(runs: [IdeationRun] = [], opportunities: [Opportunity] = []) {
        self.runs = runs
        self.opportunities = opportunities
    }

    public func count(of verdict: OpportunityVerdict, run runID: String?) -> Int {
        opportunities.filter { ($0.runID == runID || runID == nil) && $0.verdict == verdict }.count
    }
}
