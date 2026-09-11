public enum ConnectionState: String, Hashable { case connected, notConnected, unavailable, detected, missing }

public struct Connection: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var state: ConnectionState
    public var label: String        // "connected", "not connected", "unavailable", "CLI found", "not found"
    public init(id: String, name: String, state: ConnectionState, label: String) {
        self.id = id
        self.name = name
        self.state = state
        self.label = label
    }
}

public enum CapabilityValue: String, Hashable {
    case yes = "Yes", sometimes = "Sometimes", no = "No", unknown = "Unknown", notValidated = "Not validated"
}

public struct CapabilityRow: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var values: [CapabilityValue]  // one per CapabilityMatrix.providers entry
    public init(id: String, name: String, values: [CapabilityValue]) {
        self.id = id
        self.name = name
        self.values = values
    }
}

public struct CapabilityMatrix: Hashable {
    public var providers: [String]
    public var rows: [CapabilityRow]
    public var note: String
    public init(providers: [String], rows: [CapabilityRow], note: String) {
        self.providers = providers
        self.rows = rows
        self.note = note
    }
}
