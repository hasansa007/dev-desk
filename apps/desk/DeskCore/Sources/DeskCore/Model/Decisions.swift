public enum DecisionState: String, Hashable { case needsAttention, stale, answered }

public struct DecisionOption: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct DecisionAnswer: Hashable {
    public var optionTitle: String?
    public var rationale: String
    public var answeredLabel: String
    public init(optionTitle: String?, rationale: String, answeredLabel: String) {
        self.optionTitle = optionTitle
        self.rationale = rationale
        self.answeredLabel = answeredLabel
    }
}

public struct Decision: Identifiable, Hashable {
    public var id: String
    public var taskID: String?
    public var listTitle: String
    public var listMeta: String
    public var state: DecisionState
    public var question: String
    /// Inline markdown line under the question.
    public var context: String
    public var notice: String?
    public var evidence: String?
    public var options: [DecisionOption]
    public var answer: DecisionAnswer?
    public var staleReason: String?
    /// Full ADR markdown for real projects.
    public var body: String?
    public init(id: String, taskID: String? = nil, listTitle: String, listMeta: String, state: DecisionState, question: String,
                context: String, notice: String? = nil, evidence: String? = nil, options: [DecisionOption] = [],
                answer: DecisionAnswer? = nil, staleReason: String? = nil, body: String? = nil) {
        self.id = id
        self.taskID = taskID
        self.listTitle = listTitle
        self.listMeta = listMeta
        self.state = state
        self.question = question
        self.context = context
        self.notice = notice
        self.evidence = evidence
        self.options = options
        self.answer = answer
        self.staleReason = staleReason
        self.body = body
    }
}
