public enum ConnectionState: String, Hashable { case connected, notConnected, unavailable, detected, missing }

/// How a connection is signed in and out. Dev Desk never holds a credential: each CLI owns its keychain, its
/// browser dance and its token churn, so signing in is that CLI's own command, run in a terminal you watch.
public struct ConnectionAuth: Hashable {
    public let signIn: String
    /// nil for a CLI whose sign-out is not a shell command — Gemini's lives inside its own REPL, as `/auth
    /// logout`, so there is nothing here to run and no button to offer.
    public let signOut: String?
    /// Who is signed in, when the CLI says so — an account, an email, a plan. Read, shown, never stored.
    public var identity: String?
    /// `signIn` opens the tool's own interactive session rather than completing on its own, so the person
    /// finishes the sign-in there. Gemini publishes no sign-in verb at all: the documented path is to run
    /// bare `gemini` and choose from its menu. A button that claimed otherwise would run a command that
    /// does not exist.
    public let isInteractive: Bool

    public init(signIn: String, signOut: String?, identity: String? = nil, isInteractive: Bool = false) {
        self.signIn = signIn
        self.signOut = signOut
        self.identity = identity
        self.isInteractive = isInteractive
    }
}

public struct Connection: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var state: ConnectionState
    public var label: String        // "connected", "not connected", "unavailable", "CLI found", "not found"
    /// The whole story when `label` is the short version of it: the failure in full, and what to do about it.
    public var detail: String?
    /// nil when there is nothing to sign into here — a CLI that is not installed, or one this family has no
    /// verified way to run.
    public var auth: ConnectionAuth?
    /// Whether the reason this row is red is an authentication one. "no GitHub remote" is not: signing in
    /// again fixes nothing, and offering it says the wrong thing about what is wrong.
    public var isSignedOut = false

    public init(id: String, name: String, state: ConnectionState, label: String, detail: String? = nil,
                auth: ConnectionAuth? = nil, isSignedOut: Bool = false) {
        self.id = id
        self.name = name
        self.state = state
        self.label = label
        self.detail = detail
        self.auth = auth
        self.isSignedOut = isSignedOut
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
