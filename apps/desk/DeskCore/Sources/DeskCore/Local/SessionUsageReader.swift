import Foundation

/// Reads how much context an *interactive* agent session is holding, from the log its CLI writes for itself.
///
/// A task's agent runs in SwiftTerm, so the app sees a drawn screen and no JSON at all — there is no stream to
/// parse the way a background run's is parsed. Both CLIs keep a per-session JSONL transcript on disk and write
/// their token counts into it, so that file is the only place a terminal agent's meter can come from.
///
/// Every path arrives as a parameter, home included, because a reader that expands `~` itself can only be
/// tested against the developer's own sessions — which is to say, not tested.
///
/// Nothing here throws or traps. A missing directory, a foreign format, a half-written line or a file the app
/// may not open all mean the same thing: no meter. A wrong number would be worse than none.
public enum SessionUsageReader {
    /// Only the end of the transcript is read. A long session's log runs to many megabytes, this is polled
    /// every few seconds while an agent works, and every record is one whole line — so the last few hundred
    /// kilobytes always contain the newest reading, and reading more would be paid for on every poll.
    public static let tailBytes = 256 * 1024

    /// The newest reading for the session running in `directory`, or nil when there is nothing to read.
    public static func usage(agent: AgentKind, directory: String, home: String) -> ContextUsage? {
        guard let log = log(agent: agent, directory: directory, home: home),
              let text = read(log, maxBytes: tailBytes, fromEnd: true) else { return nil }
        return lastUsage(agent: agent, in: text)
    }

    /// The last line of the tail that parses as a reading. Later lines win, so the meter shows the current turn
    /// rather than the first one that happened to land inside the window.
    static func lastUsage(agent: AgentKind, in text: String) -> ContextUsage? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            if let usage = ContextUsage.read(line: String(line), agent: agent) { return usage }
        }
        return nil
    }

    // MARK: - Finding the log

    static func log(agent: AgentKind, directory: String, home: String) -> URL? {
        let home = URL(fileURLWithPath: home, isDirectory: true)
        switch agent {
        case .claude: return claudeLog(directory: directory, home: home)
        case .codex: return codexLog(directory: directory, home: home)
        case .gemini, .opencode, .antigravity: return nil
        }
    }

    /// Claude keeps one directory per working directory under `~/.claude/projects`, named after that path with
    /// every `/` and `.` turned into `-`. A session is one `.jsonl` inside it, and a directory holds every
    /// session ever run there, so the newest by modification time is the one running now.
    static func claudeLog(directory: String, home: URL) -> URL? {
        let projects = home.appendingPathComponent(".claude/projects/\(claudeSlug(directory))", isDirectory: true)
        return newest(in: projects) { $0.hasSuffix(".jsonl") }
    }

    /// `/Users/x/.devdesk/wt/a` becomes `-Users-x--devdesk-wt-a`: the leading slash and the dot of a hidden
    /// directory each become their own dash, which is why the doubled dash in the middle is correct and not a
    /// separator to collapse. Verified against a real session directory.
    static func claudeSlug(_ directory: String) -> String {
        let path = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL.path
        return String(path.map { $0 == "/" || $0 == "." ? "-" : $0 })
    }

    /// Codex files sessions by date — `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<timestamp>-<uuid>.jsonl` —
    /// and puts nothing about the working directory in the name, so the only way to tell one session's log from
    /// another's is the `cwd` in its first `session_meta` line. Newest first, so the running session is found
    /// before the finished ones, and a bounded number are opened: a developer's `~/.codex` accumulates
    /// thousands of rollouts, and this runs on a poll.
    static func codexLog(directory: String, home: URL) -> URL? {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let wanted = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL.path
        let candidates = newestFirst(under: sessions) {
            $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl")
        }
        for url in candidates.prefix(codexCandidateLimit) where codexCwd(of: url) == wanted { return url }
        return nil
    }

    /// How many rollouts are opened looking for a matching `cwd`. A session that is running is among the newest
    /// files by definition; going further would turn one poll into thousands of opens.
    static let codexCandidateLimit = 60

    /// `session_meta` is the file's first line, so only the head is read — and only a little of it, since the
    /// rest of the line is the environment the session started with.
    static func codexCwd(of url: URL) -> String? {
        guard let head = read(url, maxBytes: 64 * 1024, fromEnd: false) else { return nil }
        for line in head.split(whereSeparator: \.isNewline) {
            guard let object = ContextUsage.object(String(line)) else { continue }
            guard (object["type"] as? String) == "session_meta",
                  let payload = object["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String else { continue }
            return URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
        }
        return nil
    }

    // MARK: - Listing

    static func newest(in directory: URL, matching: (String) -> Bool) -> URL? {
        entries(of: directory, matching: matching).max { $0.modified < $1.modified }?.url
    }

    /// Every matching file below `root`, newest first. `enumerator` returns nil for a directory that does not
    /// exist, which is the ordinary case on a machine where that agent has never run.
    static func newestFirst(under root: URL, matching: (String) -> Bool) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var found: [(url: URL, modified: Date)] = []
        for case let url as URL in walker where matching(url.lastPathComponent) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            found.append((url, values.contentModificationDate ?? .distantPast))
        }
        return found.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private static func entries(of directory: URL, matching: (String) -> Bool) -> [(url: URL, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                          options: [.skipsHiddenFiles]) else { return [] }
        return contents.compactMap { url in
            guard matching(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
    }

    // MARK: - Reading

    /// A bounded read of one end of a file. `SafeFile` is this repository's version of this and would be the
    /// helper to use, but it does not fit twice over: it confines every path to the project root, and these
    /// logs live under `~/.claude` and `~/.codex`; and it refuses a file larger than the cap outright, while
    /// the whole point here is to read the tail of a file that is expected to be much larger. So its defences
    /// are repeated instead of borrowed — one descriptor, checked and then read: a regular file only, no
    /// symlink followed as the last component, no blocking open, and never more than `maxBytes`.
    static func read(_ url: URL, maxBytes: Int, fromEnd: Bool) -> String? {
        // O_NOFOLLOW refuses a symlink as the last component; O_NONBLOCK keeps a FIFO from hanging the open and
        // is cleared before reading, exactly as `SafeFile` does it.
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        if fromEnd, info.st_size > Int64(maxBytes),
           lseek(descriptor, info.st_size - Int64(maxBytes), SEEK_SET) < 0 { return nil }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        // Starting mid-file cuts the first line, and possibly a character, in half. Decoding replaces the bad
        // bytes rather than failing, and the broken first line is dropped by the parser that cannot read it.
        return String(decoding: data, as: UTF8.self)
    }
}
