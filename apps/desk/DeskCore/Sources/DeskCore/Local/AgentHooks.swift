import Foundation

/// What a terminal session reports about itself, so the app can say so when nobody is looking. A terminal is bytes
/// to the app: it cannot tell an agent that is working from one waiting on a question. The agents can, so a session
/// the app starts carries their own hooks, which drop one small file per event into a folder the app watches.
public enum TerminalEvent: Equatable {
    /// The agent needs the developer: a permission prompt, or input it has waited on. The agent's own words when it gave any.
    case question(String?)
    /// The agent finished its turn and is waiting for the next message.
    case turnFinished
    /// A message was sent and the agent is working on it. Never announced: it tells a Done task's session apart
    /// from one still writing its report, which must not be closed mid-turn.
    case turnStarted
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
    /// `.working` in a session's event folder while its agent is mid-turn, holding Dev Desk's pid. The events are
    /// consumed as they are read, so without this nothing outside the app could tell a working session from one
    /// idle at its prompt — and `install.sh` counted every idle Claude as "running" (2026-09-19). A dotfile, so the
    /// event reader skips it; the folder is deleted with the session, and the pid lets a reader ignore a marker a
    /// crashed app left behind.
    public static let workingMarker = ".working"
    /// The same, for a session that has ASKED and is waiting for the answer. A question is unfinished work too:
    /// quitting the app throws the pending decision away, which an install did on 2026-09-20 — the developer,
    /// reading the loss: *"but it was in mid of questions"*. Cleared when the next turn begins, or at exit.
    public static let askingMarker = ".asking"

    /// Writes or clears the marker for one event: a turn begun marks the session working; a finished turn, a
    /// question or an exit clears it. A bell says nothing about a turn and changes nothing.
    public static func markWorking(_ event: TerminalEvent, in directory: URL) {
        let working = directory.appendingPathComponent(workingMarker)
        let asking = directory.appendingPathComponent(askingMarker)
        let pid = Data(String(ProcessInfo.processInfo.processIdentifier).utf8)
        switch event {
        case .turnStarted:
            try? pid.write(to: working, options: .atomic)
            // Answering is what starts the next turn, so the question is answered by definition.
            try? FileManager.default.removeItem(at: asking)
        case .question:
            try? FileManager.default.removeItem(at: working)
            try? pid.write(to: asking, options: .atomic)
        case .turnFinished:
            try? FileManager.default.removeItem(at: working)
        case .exited:
            try? FileManager.default.removeItem(at: working)
            try? FileManager.default.removeItem(at: asking)
        case .bell:
            break
        }
    }

    /// Writes stdin (or `$1`) to a dotfile first and renames it, so the watcher never reads a half-written event.
    static func script(event: String, payload: String) -> String {
        #"[ -n "$DEVDESK_EVENT_DIR" ] || exit 0; t=$(mktemp "$DEVDESK_EVENT_DIR/.event.XXXXXX") && "#
            + payload + #" > "$t" && mv "$t" "$DEVDESK_EVENT_DIR/"# + event + #".${t##*.}"; exit 0"#
    }

    /// Claude's Notification hook (a permission prompt, or input waited on), Stop hook (a finished turn) and
    /// UserPromptSubmit hook (a turn begun).
    public static var claudeSettings: String {
        func hook(_ event: String) -> [[String: Any]] {
            [["hooks": [["type": "command", "command": script(event: event, payload: "cat")]]]]
        }
        let settings: [String: Any] = ["hooks": ["Notification": hook("question"), "Stop": hook("turn"),
                                                  "UserPromptSubmit": hook("prompt")]]
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
        if fileName.hasPrefix("prompt.") { return .turnStarted }
        return nil
    }
}
