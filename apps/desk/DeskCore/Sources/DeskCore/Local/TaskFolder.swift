import Foundation

/// One entry of `git worktree list --porcelain -z`.
public struct Worktree: Equatable {
    public let path: String
    public let head: String?
    /// The short name, "refs/heads/" stripped; nil when detached or bare.
    public let branch: String?
    public let isBare: Bool
    public let isDetached: Bool
}

/// `-z` ends each attribute with NUL and each entry with an empty attribute, so a path keeps its spaces and newlines.
public enum WorktreeList {
    public static func parse(_ porcelainZ: String) -> [Worktree] {
        var worktrees: [Worktree] = []
        var entry: Entry?
        for field in porcelainZ.components(separatedBy: "\0") {
            if field.hasPrefix("worktree ") {
                entry.map { worktrees.append($0.worktree) }
                entry = Entry(path: String(field.dropFirst("worktree ".count)))
            } else if field.isEmpty {
                entry.map { worktrees.append($0.worktree) }
                entry = nil
            } else if field.hasPrefix("HEAD ") {
                entry?.head = String(field.dropFirst("HEAD ".count))
            } else if field.hasPrefix("branch ") {
                entry?.branch = GitOutput.dropping("refs/heads/", from: String(field.dropFirst("branch ".count)))
            } else if field == "bare" {
                entry?.isBare = true
            } else if field == "detached" {
                entry?.isDetached = true
            }
            // "locked" and "prunable", with or without a reason, don't change which folder a branch is in.
        }
        entry.map { worktrees.append($0.worktree) }
        return worktrees
    }

    private struct Entry {
        let path: String
        var head: String?
        var branch: String?
        var isBare = false
        var isDetached = false

        init(path: String) { self.path = path }

        var worktree: Worktree { Worktree(path: path, head: head, branch: branch, isBare: isBare, isDetached: isDetached) }
    }
}

/// The folder a task's shell or agent opens in.
public struct TaskFolder: Equatable {
    public let url: URL
    /// Why it opens at the project root rather than the task's own checkout; nil when it opens in that checkout.
    public let note: String?
    /// True only when `materialise` created the worktree just now.
    public let created: Bool

    public init(url: URL, note: String?, created: Bool) {
        self.url = url
        self.note = note
        self.created = created
    }
}

public enum TaskFolderPlan: Equatable {
    case existing(URL, branch: String)
    /// Rule 1b: a worktree of this repository already at the task's own path, detached or not.
    case existingOwn(URL)
    case create(path: URL, branch: String)
    /// Rule 3, for an agent only: a new worktree at the task's own path, detached at the base ref.
    case createDetached(path: URL, baseRef: String)
    case root(URL, note: String)
}

/// The task-folder rule: the branch's own checkout, else a worktree already at the task's own path, else a new worktree for the branch
/// (or, for an agent's task with no branch yet, one detached at the base), else the project root with a note saying why.
public struct TaskFolderResolver {
    let projectRoot: URL
    let worktreeLocation: String
    let runner: CommandRunner
    let homeDirectory: URL

    public init(projectRoot: URL, worktreeLocation: String, runner: CommandRunner = ProcessRunner(),
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.projectRoot = projectRoot
        self.worktreeLocation = worktreeLocation
        self.runner = runner
        self.homeDirectory = homeDirectory
    }

    /// The shell's plan: rules 1, 1b and 2, else the project root. It only reads git's worktree list, so the plan can be shown before anything starts.
    /// `noBranchNote` replaces the no-branch note when the task says why it has no branch, as a pull request from a fork does.
    public func plan(branch: String?, taskNumber: Int?, noBranchNote: String? = nil) async -> TaskFolderPlan {
        await plan(branch: branch, taskNumber: taskNumber, unbranched: { _ in
            .root(projectRoot, note: noBranchNote ?? Self.unbranchedNote(taskNumber))
        })
    }

    /// The agent's plan: the shell's, except that a numbered task with no branch, no reason for having none and a known base ref gets a
    /// worktree detached at that ref at its own path (rule 3), where the pipeline cuts the task's branch. Anything else opens at the project root (rule 4).
    public func planAgent(branch: String?, taskNumber: Int?, noBranchNote: String?, baseRef: String?) async -> TaskFolderPlan {
        await plan(branch: branch, taskNumber: taskNumber, unbranched: { location in
            guard noBranchNote == nil, let taskNumber else { return .root(projectRoot, note: noBranchNote ?? Self.unbranchedNote(taskNumber)) }
            guard let baseRef else { return .root(projectRoot, note: Self.noBaseRefNote) }
            guard let location else { return .root(projectRoot, note: Self.locationNote) }
            return .createDetached(path: freePath(in: location, suffix: String(taskNumber)), baseRef: baseRef)
        })
    }

    /// Rules 1, 1b and 2. `unbranched` plans a task with no branch and nothing at its own path; it gets the location, nil when unusable.
    private func plan(branch: String?, taskNumber: Int?, unbranched: (URL?) -> TaskFolderPlan) async -> TaskFolderPlan {
        let branch = branch.flatMap { $0.isEmpty ? nil : $0 }
        let location = expandedLocation
        // The task's own folder is named for its number, else its branch.
        let suffix = taskNumber.map { String($0) } ?? branch.map(Self.slug)
        guard branch != nil || (location != nil && suffix != nil) else { return unbranched(location) }
        let worktrees = await worktrees()
        // A deleted worktree stays listed, as prunable, until it is pruned; a shell can't open in its missing folder.
        if let branch, let checkout = worktrees.first(where: { $0.branch == branch && Self.isDirectory($0.path) }) {
            return .existing(URL(fileURLWithPath: checkout.path, isDirectory: true), branch: branch)
        }
        if let location, let suffix, let own = ownWorktree(in: worktrees, location: location, suffix: suffix) {
            return .existingOwn(own)
        }
        guard let branch else { return unbranched(location) }
        guard let location else { return .root(projectRoot, note: Self.locationNote) }
        return .create(path: freePath(in: location, suffix: suffix ?? Self.slug(branch)), branch: branch)
    }

    /// Runs `git worktree add` for `.create` and `.createDetached` only, into a folder it makes just before. A failure or a timeout opens
    /// the project root instead, with the reason (rule 4).
    public func materialise(_ plan: TaskFolderPlan) async -> TaskFolder {
        switch plan {
        case .existing(let url, _), .existingOwn(let url): return TaskFolder(url: url, note: nil, created: false)
        case .root(let url, let note): return TaskFolder(url: url, note: note, created: false)
        case .create(let path, let branch): return await addWorktree(at: path, revision: branch, detached: false)
        case .createDetached(let path, let baseRef): return await addWorktree(at: path, revision: baseRef, detached: true)
        }
    }

    /// `git worktree add <path> <branch>`, or `git worktree add --detach <path> <base ref>`.
    private func addWorktree(at planned: URL, revision: String, detached: Bool) async -> TaskFolder {
        // The arguments carry no "--", so git would read a leading "-" as an option: -Bmain resets main.
        guard !revision.hasPrefix("-") else {
            return atRoot(revision, reason: "'\(revision)' is not a valid \(detached ? "base ref" : "branch name")")
        }
        let path: URL
        switch Self.claim(planned) {
        case .success(let claimed): path = claimed
        case .failure(let failure): return atRoot(revision, reason: failure.reason)
        }
        let reason: String
        do {
            let arguments = ["worktree", "add"] + (detached ? ["--detach"] : []) + [path.path, revision]
            let result = try await runner.run("git", GitCommand.read(arguments), in: projectRoot, timeout: CommandTimeout.worktreeAdd)
            if result.succeeded { return TaskFolder(url: path, note: nil, created: true) }
            reason = Self.errorLine(result.stderr) ?? "git exited with status \(result.status)"
        } catch {
            reason = Self.describe(error)
        }
        // rmdir removes only an empty folder, so nothing git wrote is ever deleted.
        rmdir(path.path)
        return atRoot(revision, reason: reason)
    }

    private struct ClaimFailure: Error { let reason: String }

    /// Makes the folder itself just before git runs, so one that appeared after the plan is never shared: mkdir fails on anything
    /// already at the path, a symlink included, and the next -N is tried. git accepts the empty folder.
    private static func claim(_ planned: URL) -> Result<URL, ClaimFailure> {
        let parent = planned.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            return .failure(ClaimFailure(reason: describe(error)))
        }
        var candidate = planned
        var next = 2
        while mkdir(candidate.path, 0o755) != 0 {
            let code = errno
            guard code == EEXIST else { return .failure(ClaimFailure(reason: "\(candidate.path): \(String(cString: strerror(code)))")) }
            candidate = parent.appendingPathComponent("\(planned.lastPathComponent)-\(next)", isDirectory: true)
            next += 1
        }
        return .success(candidate)
    }

    private static func describe(_ error: Error) -> String {
        var text = error.localizedDescription
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private func atRoot(_ revision: String, reason: String) -> TaskFolder {
        TaskFolder(url: projectRoot, note: "Couldn't create a worktree for \(revision), so the shell opens at the project root: \(reason)", created: false)
    }

    /// git prints progress such as "Preparing worktree (checking out …)" before its error, so the first fatal: or error: line is the reason.
    static func errorLine(_ stderr: String) -> String? {
        let lines = GitOutput.lines(stderr).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.first { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") } ?? lines.first
    }

    /// Lowercase; each run outside [a-z0-9] becomes one "-", with none at either end; at most 40 characters; "task" when nothing is left.
    static func slug(_ text: String) -> String {
        var slug = ""
        var separated = false
        for character in text.lowercased() {
            guard character.isASCII, character.isLetter || character.isNumber else {
                separated = !slug.isEmpty
                continue
            }
            if separated { slug.append("-") }
            slug.append(character)
            separated = false
        }
        var cut = String(slug.prefix(40))
        if cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? "task" : cut
    }

    /// Rule 3's plan note: a detached worktree has no branch until the pipeline's first write cuts one.
    public static let detachedNote = "The pipeline creates the task's branch here at its first write."

    static let noBaseRefNote = "No base branch is known, so the agent would open at the project root; start it by hand if you want it there."

    static let locationNote = "The worktree location must be an absolute path or start with ~/, so the shell opens at the project root."

    static func unbranchedNote(_ number: Int?) -> String {
        guard let number else { return "No branch for this task yet. The shell opens at the project root." }
        return "No branch for #\(number) yet. The shell opens at the project root; running /dev #\(number) there cuts gh-\(number)-… at its first write."
    }

    /// An unreadable list reads as no worktrees: the plan becomes a new worktree, which git refuses for a branch checked out elsewhere.
    private func worktrees() async -> [Worktree] {
        guard let result = try? await runner.run("git", GitCommand.read(["worktree", "list", "--porcelain", "-z"]), in: projectRoot, timeout: CommandTimeout.git),
              result.succeeded else { return [] }
        return WorktreeList.parse(result.stdout)
    }

    /// Rule 1b: a listed worktree at `<location>/<project>-<suffix>`, or at one of the -2, -3, … names rule 2 falls back to; the lowest wins.
    /// Folders compare by real path, since git lists a worktree by its real path: /private/var/…, not /var/….
    private func ownWorktree(in worktrees: [Worktree], location: URL, suffix: String) -> URL? {
        guard let realLocation = Self.realPath(location.path) else { return nil }
        let name = ownName(suffix)
        let owned = worktrees.compactMap { worktree -> (rank: Int, url: URL)? in
            let url = URL(fileURLWithPath: worktree.path, isDirectory: true)
            guard !worktree.isBare, let rank = Self.collisionRank(url.lastPathComponent, of: name),
                  Self.realPath(url.deletingLastPathComponent().path) == realLocation, Self.isDirectory(worktree.path) else { return nil }
            return (rank, url)
        }
        return owned.min { $0.rank < $1.rank }?.url
    }

    /// 1 for the name itself, k for `<name>-k` with k ≥ 2 written as rule 2 writes it, nil otherwise: -1, -02 and -x are other names.
    static func collisionRank(_ candidate: String, of name: String) -> Int? {
        if candidate == name { return 1 }
        guard candidate.hasPrefix(name + "-") else { return nil }
        let rest = candidate.dropFirst(name.count + 1)
        guard let k = Int(rest), k >= 2, String(k) == rest else { return nil }
        return k
    }

    /// `<project>-<suffix>`, the task's own folder name.
    private func ownName(_ suffix: String) -> String {
        "\(Self.slug(projectRoot.lastPathComponent))-\(suffix)"
    }

    /// The task's own name in the worktree location, or the first of -2, -3, … that nothing occupies.
    private func freePath(in location: URL, suffix: String) -> URL {
        let name = ownName(suffix)
        var candidate = location.appendingPathComponent(name, isDirectory: true)
        var next = 2
        while Self.occupied(candidate.path) {
            candidate = location.appendingPathComponent("\(name)-\(next)", isDirectory: true)
            next += 1
        }
        return candidate
    }

    /// nil unless the location is absolute or starts with ~/ (or is ~ itself); anything else would resolve against the app's working directory, /.
    private var expandedLocation: URL? {
        if worktreeLocation == "~" { return homeDirectory }
        if worktreeLocation.hasPrefix("~/") { return homeDirectory.appendingPathComponent(String(worktreeLocation.dropFirst(2)), isDirectory: true) }
        return worktreeLocation.hasPrefix("/") ? URL(fileURLWithPath: worktreeLocation, isDirectory: true) : nil
    }

    /// lstat, not stat: a dangling symlink still occupies its name.
    private static func occupied(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Every symlink resolved; nil when nothing is at the path.
    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
