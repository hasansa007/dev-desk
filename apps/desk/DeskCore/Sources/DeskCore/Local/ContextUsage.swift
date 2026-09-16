import Foundation

/// How much of its context an agent is using, as that agent's own CLI reports it.
///
/// Two CLIs, two shapes, and only one of them names a denominator: Codex's `token_count` carries
/// `model_context_window`, while `claude -p --output-format stream-json` reports token counts and no window at
/// any point in its stream. A percentage against an invented window would be worse than no percentage — it
/// would read as a measurement — so `window` and `percent` are both optional, and Claude simply shows its
/// count. That is why this is a struct rather than a single "percent used" number.
///
/// Parsing lives here, pure over strings, so both readers can share it: the background run parses the JSONL a
/// headless process writes to its pipe, and a task's interactive terminal parses the JSONL the CLI writes to
/// its own session log.
public struct ContextUsage: Equatable, Sendable {
    /// Tokens in context right now. It is the newest reading and never a running total: cache reads are
    /// re-counted every turn, so summing them across a run describes nothing that exists.
    public var used: Int
    /// The model's context window, when the CLI reports one; nil when it does not.
    public var window: Int?

    public init(used: Int, window: Int? = nil) {
        self.used = used
        self.window = window
    }

    /// Whole percent, and only when there is a window to divide by. Computed rather than stored so it cannot
    /// drift out of step with `window`, and guarded so a CLI that reports a window of zero yields no meter
    /// rather than a division by zero.
    public var percent: Int? {
        guard let window, window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }

    /// The one line the meter shows, wherever it is shown. Kept here rather than in each view so a background
    /// run and a task's terminal cannot word the same reading two different ways.
    public var label: String {
        guard let percent, let window else { return "\(used) tokens" }
        return "\(percent)% of context · \(used) / \(window)"
    }

    // MARK: - Claude

    /// Claude's `usage` object. What is in context is everything the model was sent for this turn: the fresh
    /// input, what was written into the prompt cache, and what was read back from it. Claude reports those
    /// three apart and sums them nowhere, so summing them is this parser's job. `output_tokens` is deliberately
    /// left out: it is what the turn produced, not what the next turn carries.
    static func claude(usage: [String: Any]) -> ContextUsage? {
        let counts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .compactMap { int(usage[$0]) }
        guard !counts.isEmpty else { return nil }
        // No window, by observation of a real run: the stream never states the model's context size, and
        // hard-coding one per model name would go stale the week a model changes.
        return ContextUsage(used: counts.reduce(0, +), window: nil)
    }

    /// One event of Claude's stream, or one line of its session log. An assistant message carries its usage
    /// under `message`; the final `result` event carries it at the top level.
    static func claude(event object: [String: Any]) -> ContextUsage? {
        let usage = (object["usage"] as? [String: Any])
            ?? ((object["message"] as? [String: Any])?["usage"] as? [String: Any])
        return usage.flatMap(claude(usage:))
    }

    /// Reads one line of Claude JSONL. Nil for every line that carries no usage, which is most of them.
    public static func claude(line: String) -> ContextUsage? {
        object(line).flatMap(claude(event:))
    }

    // MARK: - Codex

    /// Codex's `token_count` event. `codex exec --json` writes it bare on the stream, while a session rollout
    /// file wraps the identical payload in an `event_msg` envelope, so the envelope is unwrapped rather than
    /// the payload being parsed twice in two places.
    static func codex(event object: [String: Any]) -> ContextUsage? {
        let event = (object["payload"] as? [String: Any]) ?? object
        guard (event["type"] as? String) == "token_count",
              let info = event["info"] as? [String: Any] else { return nil }
        return codex(info: info)
    }

    /// A `TokenUsageInfo`. `last_token_usage` is the turn that just ran, and its `total_tokens` is what the
    /// model was holding for it — which is the meter's numerator. `total_token_usage` is the run's lifetime
    /// spend and can exceed the window many times over, so it would make a nonsense percentage.
    static func codex(info: [String: Any]) -> ContextUsage? {
        guard let last = info["last_token_usage"] as? [String: Any],
              let used = int(last["total_tokens"]) else { return nil }
        return ContextUsage(used: used, window: int(info["model_context_window"]))
    }

    /// Reads one line of Codex JSONL, in either the bare or the `payload`-wrapped shape.
    public static func codex(line: String) -> ContextUsage? {
        object(line).flatMap(codex(event:))
    }

    // MARK: - Reading

    /// Reads one line for the agent that wrote it. The two CLIs share no key, so the kind decides the parser
    /// rather than the parsers each guessing at the other's shape.
    public static func read(line: String, agent: AgentKind) -> ContextUsage? {
        switch agent {
        case .claude: return claude(line: line)
        case .codex: return codex(line: line)
        // No transcript format this app reads: the meter stays empty rather than guessing at one.
        case .gemini, .opencode, .antigravity: return nil
        }
    }

    static func object(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// JSONSerialization hands back `NSNumber`, and a count large enough to matter may arrive as a double from
    /// a producer that wrote it that way; neither should turn the meter off.
    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        return nil
    }
}
