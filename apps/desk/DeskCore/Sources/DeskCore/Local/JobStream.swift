import Foundation

/// One line of a headless run's output, after the agent's JSONL has been read.
public enum JobEvent: Equatable {
    /// The session's own id, which `--resume` needs. Claude is told one; Codex reports its own.
    case session(String)
    /// A line worth showing in the run's row.
    case line(String)
    /// The run finished. `question` is set when it stopped needing an answer rather than being done.
    case ended(text: String, question: String?)
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
            return text(in: object).map { .line($0) }
        case "result":
            let text = (object["result"] as? String) ?? (object["error"] as? String) ?? "Ended"
            return .ended(text: text, question: question(in: object, text: text))
        case "item.completed", "turn.completed":
            // Codex's shapes. Its final turn carries no result string, so the last text stands in.
            return text(in: object).map { .line($0) }
        default:
            return nil
        }
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
            case "tool_use": return (block["name"] as? String).map { "· \($0)" }
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
