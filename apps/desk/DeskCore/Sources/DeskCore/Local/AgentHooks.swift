import Foundation

/// What a terminal session reports about itself, so the app can say so when nobody is looking. A terminal is bytes
/// to the app: it cannot tell an agent that is working from one waiting on a question. The agents can, so a session
/// the app starts carries their own hooks, which drop one small file per event into a folder the app watches.
public enum TerminalEvent: Equatable {
    /// The agent needs the developer: a permission prompt, or input it has waited on. The agent's own words when it gave any.
    case question(String?)
    /// The agent finished its turn and is waiting for the next message.
    case turnFinished
    /// The session's process ended by itself, with its exit status.
    case exited(Int32)
    /// A program in the terminal rang the bell — the fallback for a CLI with no hooks, and never treated as exact.
    case bell
}

/// The hooks a Claude or Codex session is started with (verified 2026-09-17: `claude --settings <json>`,
/// `codex -c key=value`). Each writes to `$DEVDESK_EVENT_DIR`, set only in Dev Desk's own shells, and does nothing
/// where it is unset — a copied command run elsewhere stays silent rather than failing.
public enum AgentHooks {
    public static let eventDirectoryVariable = "DEVDESK_EVENT_DIR"

    /// Writes stdin (or `$1`) to a dotfile first and renames it, so the watcher never reads a half-written event.
    static func script(event: String, payload: String) -> String {
        #"[ -n "$DEVDESK_EVENT_DIR" ] || exit 0; t=$(mktemp "$DEVDESK_EVENT_DIR/.event.XXXXXX") && "#
            + payload + #" > "$t" && mv "$t" "$DEVDESK_EVENT_DIR/"# + event + #".${t##*.}"; exit 0"#
    }

    /// Claude's Notification hook (a permission prompt, or input waited on) and Stop hook (a finished turn).
    public static var claudeSettings: String {
        func hook(_ event: String) -> [[String: Any]] {
            [["hooks": [["type": "command", "command": script(event: event, payload: "cat")]]]]
        }
        let settings: [String: Any] = ["hooks": ["Notification": hook("question"), "Stop": hook("turn")]]
        let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Codex calls `notify` with the event's JSON as its last argument, and only for a finished turn. TOML literal
    /// strings take the script as written, which is why it carries no single quote.
    public static var codexNotify: String {
        let parts = ["sh", "-c", script(event: "turn", payload: #"printf %s "$1""#), "sh"]
        return "notify=[" + parts.map { "'\($0)'" }.joined(separator: ",") + "]"
    }

    /// The argv with the hooks added after the executable; any other command is returned as it was.
    public static func inject(into command: [String]) -> [String] {
        guard let executable = command.first else { return command }
        switch executable {
        case "claude": return [executable, "--settings", claudeSettings] + command.dropFirst()
        case "codex": return [executable, "-c", codexNotify] + command.dropFirst()
        default: return command
        }
    }

    /// The same, for a line typed into a shell — a door's command is typed rather than exec'd.
    public static func inject(into line: String) -> String {
        for (executable, flag, value) in [("claude", "--settings", claudeSettings), ("codex", "-c", codexNotify)]
        where line.hasPrefix(executable + " ") {
            return "\(executable) \(flag) \(DoorCommand.quoted(value))" + line.dropFirst(executable.count)
        }
        return line
    }

    /// True when a command reports its questions through hooks, so the bell is not also read as one. Only Claude:
    /// Codex's hook covers a finished turn alone, so its bell still counts.
    public static func reports(_ executable: String?) -> Bool { executable == "claude" }

    /// One event file: `question.*` carries Claude's JSON with a `message`; `turn.*` is a finished turn. A dotfile
    /// is still being written, and an unknown name is ignored.
    public static func event(fileName: String, contents: Data) -> TerminalEvent? {
        guard !fileName.hasPrefix(".") else { return nil }
        if fileName.hasPrefix("question.") {
            let json = try? JSONSerialization.jsonObject(with: contents) as? [String: Any]
            let message = (json?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Claude's idle reminder, a minute after the Stop hook already said the turn was done: the same news twice.
            if json?["notification_type"] as? String == "idle_prompt" || message == "Claude is waiting for your input" { return nil }
            return .question(message?.isEmpty == false ? message : nil)
        }
        if fileName.hasPrefix("turn.") { return .turnFinished }
        return nil
    }
}
