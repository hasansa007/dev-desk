import Foundation

/// What a background run may do without asking. It cannot prompt once it is running, so the level is granted
/// when it starts, and the developer chooses it per run.
public enum RunPermission: String, CaseIterable, Hashable {
    case readOnly, writeInRepo, everything

    public var title: String {
        switch self {
        case .readOnly: return "Read only"
        case .writeInRepo: return "Write in the repo"
        case .everything: return "Everything the door needs"
        }
    }

    public var detail: String {
        switch self {
        case .readOnly:
            return "Reads and reports. A door whose output is a written report stalls at its first write."
        case .writeInRepo:
            return "Edits files and runs git here. Anything leaving the machine ends the run as a question."
        case .everything:
            return "Including gh and push, so a run can change the tracker while you are away from it."
        }
    }

    /// Verified 2026-09-12: `--permission-mode` values from claude 2.1.269, `--sandbox` values from codex-cli 0.154.0.
    func flags(for executable: String) -> [String] {
        switch (executable, self) {
        case ("claude", .readOnly): return ["--permission-mode", "plan"]
        case ("claude", .writeInRepo): return ["--permission-mode", "acceptEdits"]
        case ("claude", .everything): return ["--dangerously-skip-permissions"]
        case ("codex", .readOnly): return ["--sandbox", "read-only"]
        case ("codex", .writeInRepo): return ["--sandbox", "workspace-write"]
        case ("codex", .everything): return ["--sandbox", "danger-full-access"]
        default: return []
        }
    }
}

public struct JobLaunch: Equatable {
    public var executable: String
    public var arguments: [String]
    /// The id the app chose, when the CLI accepts one; nil when the session's id has to be read back from its output.
    public var sessionID: String?
}

public enum JobCommand {
    /// Both builders assemble their argv through `HeadlessArgv`. Every flag they pass today takes exactly one
    /// value, so the prompt stays the final element and the argv is unchanged — but a variadic flag added to
    /// `flags(for:)` or `modeFlags(for:mode:home:)` later would have swallowed a trailing prompt (the ArchRun
    /// bug: `--allowedTools` ate the positional prompt and claude exited 1 having been given none), and the
    /// shared rule then moves the prompt in front of the flags instead of feeding it to that flag.
    ///
    /// Claude takes an id we choose (`--session-id`), so resuming never depends on parsing one out of the stream.
    /// Codex has no such flag, so its id is read from its JSONL, and `--last` is the fallback.
    public static func launch(door: String, agent name: String, arguments: [String] = [], permission: RunPermission,
                              directory: String, home: String,
                              sessionID: String = UUID().uuidString.lowercased(),
                              mode: RunMode = .standard) -> JobLaunch? {
        guard let agent = DoorCommand.agent(named: name),
              let prompt = DoorCommand.prompt(door: door, agent: name, arguments: arguments, home: home, mode: mode)
        else { return nil }
        if agent.executable == "claude" {
            return JobLaunch(executable: "claude",
                             arguments: HeadlessArgv.argv(
                                 head: ["-p"],
                                 flags: ["--output-format", "stream-json", "--verbose", "--session-id", sessionID]
                                     + permission.flags(for: "claude") + modeFlags(for: "claude", mode: mode, home: home),
                                 prompt: prompt),
                             sessionID: sessionID)
        }
        return JobLaunch(executable: agent.executable,
                         arguments: HeadlessArgv.argv(
                             head: ["exec"],
                             flags: ["--json", "-C", directory] + permission.flags(for: agent.executable)
                                 + modeFlags(for: agent.executable, mode: mode, home: home),
                             prompt: prompt),
                         sessionID: nil)
    }

    /// Answering a run's question continues that same session rather than starting a new one — under the grant
    /// it was started with. Resuming without it drops a headless run back to prompting, and a run with no
    /// terminal to prompt in stalls on its first tool call and asks again: a loop with no way out. The mode
    /// travels with it for the same reason: a delegate run resumed without its worker has nothing to hand to.
    public static func resume(agent name: String, sessionID: String?, answer: String,
                              permission: RunPermission, home: String, mode: RunMode = .standard) -> JobLaunch? {
        guard let agent = DoorCommand.agent(named: name) else { return nil }
        if agent.executable == "claude" {
            guard let sessionID else { return nil }
            return JobLaunch(executable: "claude",
                             arguments: HeadlessArgv.argv(
                                 head: ["-p"],
                                 flags: ["--output-format", "stream-json", "--verbose", "--resume", sessionID]
                                     + permission.flags(for: "claude") + modeFlags(for: "claude", mode: mode, home: home),
                                 prompt: answer),
                             sessionID: sessionID)
        }
        return JobLaunch(executable: agent.executable,
                         arguments: HeadlessArgv.argv(
                             head: ["exec", "resume", sessionID ?? "--last"],
                             flags: ["--json"] + permission.flags(for: agent.executable)
                                 + modeFlags(for: agent.executable, mode: mode, home: home),
                             prompt: answer),
                         sessionID: sessionID)
    }

    /// The one worker Delegate gives claude, in the shape `--agents` documents: a name, what it is for, and its
    /// prompt. Serialised rather than typed out so a future edit to the wording cannot leave the JSON unclosed.
    /// Verified: `--agents <json>` and its `{"name": {"description", "prompt"}}` shape, from claude 2.1.270's `--help`.
    static let delegateAgentsJSON: String = {
        let agents = ["worker": ["description": "Implements one self-contained brief from the orchestrator",
                                 "prompt": "Implement one self-contained brief and report what changed."]]
        let data = try? JSONSerialization.data(withJSONObject: agents, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }()

    /// Where codex reads a Delegate profile from. `--profile` names a config file under `$CODEX_HOME`, and
    /// naming one that is not there fails the run before the prompt is read, so the flag is added only when the
    /// developer has written that file. Without it the prompt alone carries the mode.
    /// Verified: `-p, --profile <CONFIG_PROFILE_V2>` layers `$CODEX_HOME/<name>.config.toml`, from codex-cli 0.154.0's `exec --help`.
    static func codexDelegateProfilePath(home: String) -> String { "\(home)/.codex/delegate.config.toml" }

    static func modeFlags(for executable: String, mode: RunMode, home: String) -> [String] {
        guard mode == .delegate else { return [] }
        switch executable {
        case "claude": return ["--agents", delegateAgentsJSON]
        case "codex":
            return FileManager.default.fileExists(atPath: codexDelegateProfilePath(home: home)) ? ["--profile", "delegate"] : []
        default: return []
        }
    }
}

/// What the app reads back from a finished run. `message` is its last message, which is the question when it stopped to ask.
public struct JobOutcome: Equatable {
    public var sessionID: String?
    public var message: String
    public var isError: Bool
    /// How many tool calls the granted permission refused; a run that wanted more than it was given says so.
    public var denials: Int

    public init(sessionID: String?, message: String, isError: Bool, denials: Int) {
        self.sessionID = sessionID
        self.message = message
        self.isError = isError
        self.denials = denials
    }
}

public enum JobLog {
    /// Claude's stream-json ends with one `result` event carrying `session_id`, `result`, `is_error` and
    /// `permission_denials`. Shape verified 2026-09-12 against claude 2.1.269, by running one and resuming it.
    public static func outcome(streamJSON: String) -> JobOutcome? {
        for line in streamJSON.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "result" else { continue }
            return JobOutcome(sessionID: object["session_id"] as? String,
                              message: object["result"] as? String ?? "",
                              isError: object["is_error"] as? Bool ?? false,
                              denials: (object["permission_denials"] as? [Any])?.count ?? 0)
        }
        return nil
    }
}
