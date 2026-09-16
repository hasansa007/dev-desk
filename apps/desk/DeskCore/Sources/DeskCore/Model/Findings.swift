public enum FindingCategory: String, CaseIterable, Hashable {
    case new = "New"
    case knownNewEvidence = "Known · new evidence"
    case needsDecision = "Needs a decision"
    case closedOrDeclined = "Closed or declined"
}

extension FindingCategory {
    /// What this category is actually asking of the developer. "Needs a decision" named a decision without
    /// ever saying what it was or where to make it — the label promised a question the app never asked.
    public var decision: (title: String, message: String)? {
        switch self {
        case .new:
            return nil
        case .needsDecision:
            return ("This one is yours to decide",
                    "dev:findings could not confirm it, so it held it back and filed nothing — it is not claiming a defect. "
                        + "Add it to the backlog to have it worked on anyway, or ignore it. Either way it stays in the report.")
        case .knownNewEvidence:
            return ("An issue already covers this",
                    "The run matched it to existing work and brought new evidence. Compare them before filing a second issue for the same thing.")
        case .closedOrDeclined:
            return ("This was closed or declined before",
                    "Someone already decided against it. Reopen it only if this run brought something the decision did not have.")
        }
    }
}

/// Which half of the report a finding came out of. `dev:findings` writes them in one report but they are two
/// different claims: a defect is something that misbehaves, a drift is the shape of the code disagreeing with
/// the shape it is documented to have. The card said neither, so the two read as one list.
public enum FindingKind: String, CaseIterable, Hashable {
    case defect = "Defect"
    case architecture = "Architecture"
}

public struct FindingsRun: Identifiable, Hashable {
    public var id: String
    public var label: String       // "today 09:40", or a report file stem
    public var revision: String?   // "9c2e410"
    public init(id: String, label: String, revision: String?) {
        self.id = id
        self.label = label
        self.revision = revision
    }
}

public struct CompareCard: Hashable {
    public var title: String
    public var body: String
    public var meta: String         // may contain "\n"; the sheet renders it with line breaks
    public var metaMonospaced: Bool
    public init(title: String, body: String, meta: String, metaMonospaced: Bool) {
        self.title = title
        self.body = body
        self.meta = meta
        self.metaMonospaced = metaMonospaced
    }
}

public struct RelationshipOption: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct Reconciliation: Hashable {
    public var candidateIssue: Int
    public var statusNote: String
    public var guidance: [String]
    public var findingCard: CompareCard
    public var issueCard: CompareCard
    public var relationships: [RelationshipOption]
    public var proposedUpdate: [String]
    public var deliveryNote: String
    /// Set after the developer queues the update in the demo.
    public var queuedNote: String?
    public init(candidateIssue: Int, statusNote: String, guidance: [String], findingCard: CompareCard, issueCard: CompareCard,
                relationships: [RelationshipOption], proposedUpdate: [String], deliveryNote: String, queuedNote: String? = nil) {
        self.candidateIssue = candidateIssue
        self.statusNote = statusNote
        self.guidance = guidance
        self.findingCard = findingCard
        self.issueCard = issueCard
        self.relationships = relationships
        self.proposedUpdate = proposedUpdate
        self.deliveryNote = deliveryNote
        self.queuedNote = queuedNote
    }
}

public struct Finding: Identifiable, Hashable {
    public var id: String
    public var runID: String
    public var title: String
    public var listDetail: String
    public var categories: Set<FindingCategory>
    /// Defect unless the report put it under ARCHITECTURE. Everything the door writes outside that section is
    /// a defect, so the default is the right answer for every caller with no section to read it from.
    public var kind: FindingKind
    public var summary: String
    public var verificationLabel: String
    public var locations: [String]
    public var limits: String
    public var reconcile: Reconciliation?
    public var historyNote: String?
    /// Type, group, the code it touches and the tickets it meets — only a grouped report writes these (ADR 0040).
    public var coordination: FindingsCoordination
    public init(id: String, runID: String, title: String, listDetail: String, categories: Set<FindingCategory>, summary: String,
                verificationLabel: String, locations: [String], limits: String, reconcile: Reconciliation? = nil, historyNote: String? = nil,
                kind: FindingKind = .defect, coordination: FindingsCoordination = FindingsCoordination()) {
        self.coordination = coordination
        self.id = id
        self.runID = runID
        self.title = title
        self.listDetail = listDetail
        self.categories = categories
        self.kind = kind
        self.summary = summary
        self.verificationLabel = verificationLabel
        self.locations = locations
        self.limits = limits
        self.reconcile = reconcile
        self.historyNote = historyNote
    }

    /// What `dev:create-issue` is handed when a finding is filed. The door drafts the issue; this gives it the
    /// claim, the evidence, and where the claim came from, so the issue can be judged without the report.
    public var backlogDescription: String {
        let sources = locations.isEmpty ? "" : " Sources: \(locations.joined(separator: ", "))."
        let scope = coordination.scopeLines.isEmpty ? "" : " Scope: \(coordination.scopeLines.joined(separator: "; "))."
        return "\(title). \(summary)\(sources)\(scope) Found by dev:findings, run \(runID); \(verificationLabel). \(limits)"
    }
}

public struct FindingsReport: Hashable {
    public var runs: [FindingsRun]
    public var findings: [Finding]
    /// The report's `## GROUPS`, for every run read. Empty for a report written before ADR 0040.
    public var groups: [FindingsGroup]
    /// Shown under the list, e.g. why issue search is unavailable.
    public var searchNote: String?
    public init(runs: [FindingsRun], findings: [Finding], groups: [FindingsGroup] = [], searchNote: String? = nil) {
        self.runs = runs
        self.findings = findings
        self.groups = groups
        self.searchNote = searchNote
    }

    public func count(of category: FindingCategory, run runID: String?) -> Int {
        findings.filter { ($0.runID == runID || runID == nil) && $0.categories.contains(category) }.count
    }

    /// The same count for the other half of what a finding is, so its filter chip can carry a number too.
    public func count(of kind: FindingKind, run runID: String?) -> Int {
        findings.filter { ($0.runID == runID || runID == nil) && $0.kind == kind }.count
    }
}
