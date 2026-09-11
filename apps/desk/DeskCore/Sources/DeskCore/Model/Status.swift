public enum StatusTone: String, Codable, Hashable {
    case running, waiting, failed, neutral, info, ended
}

public struct StatusBadge: Hashable {
    public var tone: StatusTone
    public var label: String
    public var pulses: Bool
    /// SF Symbol drawn before the label, e.g. "questionmark.diamond" for a pending decision.
    public var symbol: String?

    public init(_ tone: StatusTone, _ label: String, pulses: Bool = false, symbol: String? = nil) {
        self.tone = tone
        self.label = label
        self.pulses = pulses
        self.symbol = symbol
    }
}

public struct KeyValue: Hashable {
    public var key: String
    public var value: String
    public var monospaced: Bool

    public init(_ key: String, _ value: String, monospaced: Bool = false) {
        self.key = key
        self.value = value
        self.monospaced = monospaced
    }
}
