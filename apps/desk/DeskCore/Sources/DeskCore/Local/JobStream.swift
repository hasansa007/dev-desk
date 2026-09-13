import Foundation

/// One line of a headless run's output, after the agent's JSONL has been read.
public enum JobEvent: Equatable {
    /// The session's own id, which `--resume` needs. Claude is told one; Codex reports its own.
    case session(String)
    /// A line worth showing in the run's row.
    case line(String)
    /// The run finished. `question` is set when it stopped needing an answer rather than being done.
    case ended(text: String, question: String?)
    /// How much context the run is holding, for the lines whose only news is that reading — Codex's
    /// `token_count`, and an assistant message that reported usage without saying anything.
    case usage(ContextUsage)
}

/// Reads what `claude -p --output-format stream-json` and `codex exec --json` write, one line at a time.
///
/// Kept apart from anything that spawns a process, so the shapes below are tested against real recorded
/// output rather than against a running agent: a parser that can only be exercised by starting an agent is a
/// parser nobody re-tests once it works.
public enum JobStream {
    public static func event(from line: String) -> JobEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Not JSON: agents print plain notices too, and dropping them would hide the reason a run stalled.
            return trimmed.isEmpty ? nil : .line(trimmed)
        }
        if let id = object["session_id"] as? String, (object["type"] as? String) == "system" {
            return .session(id)
        }
        switch object["type"] as? String {
        case "assistant", "user":
            // The line wins whenever there is one. An assistant message can carry both its text and a fresh
            // usage reading, and one return can only say one of them: dropping the text to gain a number would
            // take log output away, so the reading is left to `usage(from:)`, which callers read beside the
            // event. Only a message with nothing to show reports its usage as the event itself.
            if let text = text(in: object) { return .line(text) }
            return ContextUsage.claude(event: object).map { .usage($0) }
        case "result":
            let text = (object["result"] as? String) ?? (object["error"] as? String) ?? "Ended"
            return .ended(text: text, question: question(in: object, text: text))
        case "item.completed", "turn.completed":
            // Codex's shapes. Its final turn carries no result string, so the last text stands in.
            return text(in: object).map { .line($0) }
        case "token_count", "event_msg":
            // Codex's reading, which says nothing else, so it is the whole event. `event_msg` is the envelope
            // the same payload arrives in inside a session rollout file.
            return ContextUsage.codex(event: object).map { .usage($0) }
        default:
            return nil
        }
    }

    /// The context reading a line carries, whatever else that line is. It is read apart from `event(from:)`
    /// precisely because one line can be two pieces of news at once — a tool call to log AND a fresh reading —
    /// and a single returned event would have to lose one of them.
    public static func usage(from line: String) -> ContextUsage? {
        guard let object = ContextUsage.object(line) else { return nil }
        return ContextUsage.claude(event: object) ?? ContextUsage.codex(event: object)
    }

    /// A run given `RunPermission` it turned out to need more than stops rather than prompting — there is no
    /// terminal to prompt in. That stop is the question, and it is what the answer box resumes from.
    ///
    /// Only a stop-to-ask qualifies. Treating every `is_error` as a question turns an exhausted credit balance
    /// or a bad key into "Waiting for your answer" forever — the row never corrects, because an asking job
    /// ignores its own exit, and answering resumes a session that fails identically.
    static func question(in object: [String: Any], text: String) -> String? {
        let subtype = ((object["subtype"] as? String) ?? "").lowercased()
        guard subtype == "error_max_turns" || subtype.contains("permission") || subtype.contains("interrupt") else { return nil }
        return text
    }

    static func text(in object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return (object["text"] as? String)?.nonEmpty
        }
        let parts = content.compactMap { block -> String? in
            switch block["type"] as? String {
            case "text": return (block["text"] as? String)?.nonEmpty
            case "tool_use": return toolUse(block)
            case "tool_result": return failedResult(block)
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// The tool AND what it was pointed at. A log of "Read / Read / Bash / Bash / Bash" says a run is doing
    /// something and nothing else — you cannot see what it read, whether it is making progress, or that it has
    /// run the same failing command eleven times.
    static func toolUse(_ block: [String: Any]) -> String? {
        guard let name = (block["name"] as? String)?.nonEmpty else { return nil }
        let input = block["input"] as? [String: Any] ?? [:]
        return "· " + [name, argument(in: input)].compactMap { $0 }.joined(separator: " ")
    }

    /// What a tool call was about, from the field that carries it. `description` first: an agent writes one
    /// for a shell command precisely because the command itself is not the readable version.
    static let argumentKeys = ["description", "command", "file_path", "path", "pattern", "url", "query", "prompt"]

    static func argument(in input: [String: Any]) -> String? {
        for key in argumentKeys {
            if let value = (input[key] as? String)?.nonEmpty { return oneLine(value) }
        }
        return nil
    }

    /// A tool that failed is the thing worth seeing in a run with no terminal — a loop is a failure repeating.
    static func failedResult(_ block: [String: Any]) -> String? {
        guard (block["is_error"] as? Bool) == true else { return nil }
        if let text = (block["content"] as? String)?.nonEmpty { return "! " + oneLine(text) }
        if let content = block["content"] as? [[String: Any]] {
            let text = content.compactMap { ($0["text"] as? String)?.nonEmpty }.joined(separator: " ")
            return text.isEmpty ? "! Failed" : "! " + oneLine(text)
        }
        return "! Failed"
    }

    /// One line, capped. A row is a row: a pasted file or a heredoc would otherwise be the whole log.
    static func oneLine(_ text: String, limit: Int = 120) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }
}

extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
