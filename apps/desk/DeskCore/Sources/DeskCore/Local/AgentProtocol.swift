import Foundation

/// How one CLI reports the four facts Dev Desk needs about a session — a turn began, a turn ended, it asked you
/// something, it exited — and what to do where the CLI reports none of them.
///
/// The CLIs differ and will keep differing, so the app reads one contract and each CLI gets an adapter behind it
/// (decided 2026-09-20). What the adapters cannot supply, the terminal does: Dev Desk owns the PTY, so a line
/// SENT to a session is a turn begun whatever is running in it.
public struct AgentProtocol: Equatable {
    public let kind: AgentKind?
    /// The CLI tells us when a turn ends (Claude's Stop, Codex's notify). Without it a session is working until
    /// its process goes, because nothing else can say otherwise.
    public let reportsTurnEnd: Bool
    /// The CLI tells us when it ASKS, apart from finishing (Claude's Notification). Without it a finished turn is
    /// read as a question: the session is waiting for you either way, and an install must not eat a pending one.
    public let reportsQuestions: Bool

    public static let claude = AgentProtocol(kind: .claude, reportsTurnEnd: true, reportsQuestions: true)
    public static let codex = AgentProtocol(kind: .codex, reportsTurnEnd: true, reportsQuestions: false)
    /// gemini, opencode, antigravity, and a plain shell: nothing is reported, so nothing is assumed.
    public static let silent = AgentProtocol(kind: nil, reportsTurnEnd: false, reportsQuestions: false)

    public static func of(_ executable: String?) -> AgentProtocol {
        switch executable.flatMap(AgentKind.init(rawValue:)) {
        case .claude: return .claude
        case .codex: return .codex
        default: return .silent
        }
    }

    /// True while the session cannot be ended without losing something: mid-turn, or waiting with a question
    /// nobody answered. A CLI that reports no turn end is working from the moment it starts until it exits.
    public var mustNotBeEndedWhileIdle: Bool { !reportsTurnEnd }
}
