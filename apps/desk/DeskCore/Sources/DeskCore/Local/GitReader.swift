import Foundation

struct GitCommit: Equatable {
    let sha: String
    let author: String
    let date: String
    let subject: String
}

struct NumstatEntry: Equatable {
    let path: String
    let additions: Int?
    let deletions: Int?
}

struct BranchFacts: Equatable {
    var name: String
    var unmerged: Int
    /// Whether `rev-list` actually answered. Without this, an unreadable base and a branch with nothing to
    /// merge are both 0 — and anything reading 0 as "already merged" is reading a failure as a fact.
    var counted = false
    /// When the branch's tip was committed, from the same `for-each-ref` that already sorts by it. A branch
    /// with unmerged commits is In Progress by git's rule; without this, a dead branch and live work look alike.
    var lastCommit: Date?
    /// The count, or nil when git never gave one. Everything that decides anything reads this, not `unmerged`.
    var countedUnmerged: Int? { counted ? unmerged : nil }

    /// Set only when the branch is checked out in a worktree other than the opened one.
    var worktree: String?
    var commits: [GitCommit] = []
    var files: [NumstatEntry] = []
    var diffs: [String: FileDiff] = [:]
    /// Why `git log` failed, so Activity says so instead of showing no commits.
    var logFailure: String? = nil
    /// Why `git diff` failed, so Changes says so instead of showing no files.
    var diffFailure: String? = nil
    /// The commit the branch points at, so a branch still at a merged pull request's head reads as merged.
    var head: String? = nil
}

struct GitFacts: Equatable {
    var base: String?
    /// The fully qualified form commands use, e.g. refs/heads/main.
    var baseRef: String?
    var baseShort: String?
    var branches: [BranchFacts]
    /// The total count of non-base local branches when more than the cap exist, so the note can say what was left out.
    var truncatedBranchCount: Int? = nil
}

struct GitReadFailure: Error {
    let detail: String
}

/// Pure parsers for the git output GitReader collects.
enum GitOutput {
    static let baseCandidates = ["staging", "develop", "main", "master"]
    static let maxDiffFiles = 200
    static let maxDiffLines = 1500
    static let maxBranches = 200

    /// Splits on "\n" only, so a form feed or U+2028 inside a line never splits it; a trailing "\r" is dropped.
    static func lines(_ text: String) -> [String] {
        var result = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if result.last == "" { result.removeLast() }
        return result
    }

    static func lastNonEmptyLine(_ text: String) -> String? {
        lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
    }

    /// From `git config --type=bool --get-regexp` output, whether any promisor remote is on; nil when a line isn't git's normalised true/false.
    /// The value is the last word, since a remote's name may itself hold a space.
    static func anyPromisorIsOn(_ boolOutput: String) -> Bool? {
        let entries = lines(boolOutput)
        guard !entries.isEmpty, entries.allSatisfy({ $0.hasSuffix(" true") || $0.hasSuffix(" false") }) else { return nil }
        return entries.contains { $0.hasSuffix(" true") }
    }

    /// Names from `for-each-ref --format=%(refname) refs/heads`; the full form stays exact when a tag shares a branch's name.
    static func preferredBase(remoteBranches output: String) -> String? {
        preferredBase(among: lines(output).compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            return name.hasPrefix("origin/") ? String(name.dropFirst("origin/".count)) : nil
        })
    }

    static func preferredBase(among names: [String]) -> String? {
        baseCandidates.first { names.contains($0) }
    }

    static func worktrees(_ porcelain: String) -> [String: String] {
        var map: [String: String] = [:]
        var path: String?
        for line in lines(porcelain) {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/"), let path {
                map[String(line.dropFirst("branch refs/heads/".count))] = path
            } else if line.isEmpty {
                path = nil
            }
        }
        return map
    }

    static func commits(_ log: String) -> [GitCommit] {
        lines(log).compactMap { line in
            let fields = line.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            return GitCommit(sha: fields[0], author: fields[1], date: fields[2], subject: fields[3])
        }
    }

    static func numstat(_ output: String) -> [NumstatEntry] {
        lines(output).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { return nil }
            return NumstatEntry(path: renamedPath(unquote(fields[2])), additions: Int(fields[0]), deletions: Int(fields[1]))
        }
    }

    static func fileDiffs(_ diff: String, maxFiles: Int = maxDiffFiles, maxLines: Int = maxDiffLines) -> [FileDiff] {
        var files: [FileDiff] = []
        var current: FileDiffBuilder?
        for line in lines(diff) {
            if line.hasPrefix("diff --git ") {
                if let builder = current { files.append(builder.fileDiff) }
                if files.count == maxFiles { return files }
                current = FileDiffBuilder(header: line, maxLines: maxLines)
            } else {
                current?.consume(line)
            }
        }
        if let builder = current { files.append(builder.fileDiff) }
        return files
    }

    /// "docs/{old => new}/a.md" and "a.md => b.md" name the new path, the one the unified diff uses.
    static func renamedPath(_ path: String) -> String {
        if let open = path.range(of: "{"),
           let arrow = path.range(of: " => ", range: open.upperBound..<path.endIndex),
           let close = path.range(of: "}", range: arrow.upperBound..<path.endIndex) {
            var joined = String(path[..<open.lowerBound] + path[arrow.upperBound..<close.lowerBound] + path[close.upperBound...])
                .replacingOccurrences(of: "//", with: "/")
            if joined.hasPrefix("/") { joined.removeFirst() }
            return joined
        }
        if let arrow = path.range(of: " => ") { return String(path[arrow.upperBound...]) }
        return path
    }

    /// Reverses git's C-style path quoting, e.g. "caf\303\251.txt" in quotes becomes café.txt.
    static func unquote(_ raw: String) -> String {
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        let utf8 = Array(raw.utf8)
        guard utf8.count >= 2, utf8.first == quote, utf8.last == quote else { return raw }
        let escapes: [UInt8: UInt8] = [UInt8(ascii: "n"): 0x0A, UInt8(ascii: "t"): 0x09, UInt8(ascii: "r"): 0x0D,
                                       UInt8(ascii: "a"): 0x07, UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "v"): 0x0B]
        let body = utf8[1..<(utf8.count - 1)]
        var bytes: [UInt8] = []
        var index = body.startIndex
        while index < body.endIndex {
            let next = index + 1
            guard body[index] == backslash, next < body.endIndex else {
                bytes.append(body[index])
                index = next
                continue
            }
            let octal = body[next..<min(next + 3, body.endIndex)]
            if octal.count == 3, octal.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "7")).contains($0) }) {
                bytes.append(octal.reduce(UInt8(0)) { $0 &* 8 &+ ($1 &- UInt8(ascii: "0")) })
                index = next + 3
            } else {
                bytes.append(escapes[body[next]] ?? body[next])
                index = next + 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The path from a "diff --git a/X b/Y" line, for blocks that carry no ---/+++ or rename lines.
    static func headerPath(_ header: String) -> String {
        let rest = String(header.dropFirst("diff --git ".count))
        if rest.hasSuffix("\""), let open = rest.range(of: " \"", options: .backwards) {
            return dropping("b/", from: unquote(String(rest[rest.index(after: open.lowerBound)...])))
        }
        var last: String?
        var searchFrom = rest.startIndex
        while let separator = rest.range(of: " b/", range: searchFrom..<rest.endIndex) {
            let old = dropping("a/", from: String(rest[..<separator.lowerBound]))
            let new = String(rest[separator.upperBound...])
            if old == new { return new }
            last = new
            searchFrom = separator.upperBound
        }
        return last ?? rest
    }

    static func dropping(_ prefix: String, from path: String) -> String {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

private struct FileDiffBuilder {
    let header: String
    let maxLines: Int
    private var newPath: String?
    private var oldPath: String?
    private var renamedTo: String?
    private var hunks: [DiffHunk] = []
    private var lineCount = 0
    private var truncated = false

    init(header: String, maxLines: Int) {
        self.header = header
        self.maxLines = maxLines
    }

    var fileDiff: FileDiff {
        FileDiff(path: newPath ?? oldPath ?? renamedTo ?? GitOutput.headerPath(header), hunks: hunks, truncated: truncated)
    }

    mutating func consume(_ line: String) {
        if line.hasPrefix("@@") {
            if lineCount >= maxLines { truncated = true } else { hunks.append(DiffHunk(header: line, lines: [])) }
            return
        }
        guard !hunks.isEmpty else { return readMetadata(line) }
        let kind: DiffLine.Kind
        switch line.first {
        case "+": kind = .addition
        case "-": kind = .deletion
        case " ", nil: kind = .context
        default: return
        }
        guard lineCount < maxLines else {
            truncated = true
            return
        }
        hunks[hunks.count - 1].lines.append(DiffLine(kind, String(line.dropFirst())))
        lineCount += 1
    }

    private mutating func readMetadata(_ line: String) {
        if line.hasPrefix("+++ "), let path = label(line, prefix: "b/") {
            newPath = path
        } else if line.hasPrefix("--- "), let path = label(line, prefix: "a/") {
            oldPath = path
        } else if line.hasPrefix("rename to ") {
            renamedTo = GitOutput.unquote(String(line.dropFirst("rename to ".count)))
        }
    }

    /// Git appends a tab to the label when the path contains a space.
    private func label(_ line: String, prefix: String) -> String? {
        var value = String(line.dropFirst(4))
        if value.hasSuffix("\t") { value.removeLast() }
        guard value != "/dev/null" else { return nil }
        return GitOutput.dropping(prefix, from: GitOutput.unquote(value))
    }
}

extension Array {
    /// Runs at most `limit` transforms at once and keeps the input order.
    func concurrentMap<T>(limit: Int = 4, _ transform: @escaping (Element) async -> T) async -> [T] {
        var results = [T?](repeating: nil, count: count)
        await withTaskGroup(of: (Int, T).self) { group in
            var next = 0
            func startNext() {
                guard next < count else { return }
                let index = next
                group.addTask { (index, await transform(self[index])) }
                next += 1
            }
            for _ in 0..<limit { startNext() }
            while let (index, value) = await group.next() {
                results[index] = value
                startNext()
            }
        }
        return results.compactMap { $0 }
    }
}

struct GitReader {
    let root: URL
    let runner: CommandRunner

    func read(toplevel: String, currentBranch: String) async -> GitFacts {
        async let remote = output(["branch", "-r", "--format=%(refname:short)"])
        async let local = output(["for-each-ref", "--format=%(refname) %(objectname) %(committerdate:unix)", "--sort=-committerdate", "refs/heads"])
        async let porcelain = output(["worktree", "list", "--porcelain"])
        let refs = GitOutput.lines(await local ?? "").compactMap(Self.refAndHead)
        let localNames = refs.map(\.name)
        let heads = Dictionary(refs.compactMap { ref in ref.head.map { (ref.name, $0) } }, uniquingKeysWith: { first, _ in first })
        let committed = Dictionary(refs.compactMap { ref in ref.committed.map { (ref.name, $0) } }, uniquingKeysWith: { first, _ in first })
        let (base, baseRef) = await resolveBase(remote: await remote ?? "", local: localNames, current: currentBranch)
        var baseShort: String?
        if let baseRef { baseShort = trimmed(await output(["rev-parse", "--short", baseRef])) }
        let worktrees = GitOutput.worktrees(await porcelain ?? "")
        let here = Self.canonical(toplevel)
        // Cap the fan-out: rev-list, log and two diffs run per branch, and the newest-committed branches matter most.
        let candidates = localNames.filter { $0 != base }
        let shown = Array(candidates.prefix(GitOutput.maxBranches))
        let branches = await shown.concurrentMap { name in
            let elsewhere = worktrees[name].flatMap { Self.canonical($0) == here ? nil : $0 }
            var facts = await branchFacts(name, baseRef: baseRef, worktree: elsewhere)
            facts.head = heads[name]
            facts.lastCommit = committed[name]
            return facts
        }
        return GitFacts(base: base, baseRef: baseRef, baseShort: baseShort, branches: branches,
                        truncatedBranchCount: candidates.count > GitOutput.maxBranches ? candidates.count : nil)
    }

    /// A `for-each-ref --format=%(refname) %(objectname) %(committerdate:unix)` line; ref names can't hold spaces,
    /// and a line missing either trailing field keeps that one nil rather than dropping the branch.
    private static func refAndHead(_ line: String) -> (name: String, head: String?, committed: Date?)? {
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        guard let ref = parts.first, ref.hasPrefix("refs/heads/") else { return nil }
        let seconds = parts.count > 2 ? TimeInterval(parts[2]) : nil
        return (String(ref.dropFirst("refs/heads/".count)),
                parts.count > 1 ? parts[1] : nil,
                seconds.map(Date.init(timeIntervalSince1970:)))
    }

    /// dev.py's resolve_base plus a local candidate before the current branch; refs are fully qualified so no name can read as an option.
    private func resolveBase(remote: String, local: [String], current: String) async -> (name: String?, ref: String?) {
        // Origin's copy even when a local branch shares its name: a local base that lags counts merged work as unmerged.
        if let name = GitOutput.preferredBase(remoteBranches: remote) { return (name, "refs/remotes/origin/\(name)") }
        if let name = GitOutput.preferredBase(among: local) { return (name, "refs/heads/\(name)") }
        if current.isEmpty { return (nil, nil) }
        return (current, current == "HEAD" ? "HEAD" : "refs/heads/\(current)")
    }

    private func branchFacts(_ name: String, baseRef: String?, worktree: String?) async -> BranchFacts {
        var facts = BranchFacts(name: name, unmerged: 0, worktree: worktree)
        let ref = "refs/heads/\(name)"
        guard let baseRef,
              let count = Int(trimmed(await output(["rev-list", "--count", "\(baseRef)..\(ref)"])) ?? "") else { return facts }
        facts.counted = true
        facts.unmerged = count
        guard count > 0 else { return facts }
        async let log = read(["log", "--format=%h%x1f%an%x1f%aI%x1f%s", "-n", "50", "\(baseRef)..\(ref)"])
        async let numstat = read(["diff", "--numstat", "--no-textconv", "\(baseRef)...\(ref)"])
        async let diff = read(["diff", "--no-color", "--no-ext-diff", "--no-textconv", "-U3", "\(baseRef)...\(ref)"])
        switch await log {
        case .success(let text): facts.commits = GitOutput.commits(text)
        case .failure(let failure): facts.logFailure = failure.detail
        }
        switch (await numstat, await diff) {
        case (.success(let stat), .success(let text)):
            facts.files = GitOutput.numstat(stat)
            facts.diffs = Dictionary(GitOutput.fileDiffs(text).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        case (.failure(let failure), _), (_, .failure(let failure)):
            facts.diffFailure = failure.detail
        }
        return facts
    }

    /// Untrimmed stdout of a successful (hardened) git call, or why it failed, so a diff keeps its last context line.
    private func read(_ arguments: [String]) async -> Result<String, GitReadFailure> {
        do {
            let result = try await runner.run("git", GitCommand.read(arguments), in: root, timeout: CommandTimeout.git)
            guard result.succeeded else {
                return .failure(GitReadFailure(detail: Markdown.reason(GitOutput.lastNonEmptyLine(result.stderr) ?? "git exited with status \(result.status)")))
            }
            return .success(result.stdout)
        } catch {
            var text = error.localizedDescription
            if text.hasSuffix(".") { text.removeLast() }
            return .failure(GitReadFailure(detail: Markdown.reason(text)))
        }
    }

    private func output(_ arguments: [String]) async -> String? {
        try? await read(arguments).get()
    }

    private func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
