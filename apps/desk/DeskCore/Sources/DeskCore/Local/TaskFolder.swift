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

/// The folder a task's shell opens in.
public struct TaskFolder: Equatable {
    public let url: URL
    /// Why the shell opens at the project root rather than the task's own checkout; nil when it opens in that checkout.
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
    case create(path: URL, branch: String)
    case root(URL, note: String)
}

/// The task-folder rule: the branch's own checkout, else a new worktree for it, else the project root with a note saying why.
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

    /// Rules 1–3 of the task-folder rule. It only reads git's worktree list, so the plan can be shown before anything starts.
    /// `noBranchNote` replaces rule 3's note when the task says why it has no branch, as a pull request from a fork does.
    public func plan(branch: String?, taskNumber: Int?, noBranchNote: String? = nil) async -> TaskFolderPlan {
        guard let branch, !branch.isEmpty else { return .root(projectRoot, note: noBranchNote ?? Self.unbranchedNote(taskNumber)) }
        // A deleted worktree stays listed, as prunable, until it is pruned; a shell can't open in its missing folder.
        if let checkout = await worktrees().first(where: { $0.branch == branch && Self.isDirectory($0.path) }) {
            return .existing(URL(fileURLWithPath: checkout.path, isDirectory: true), branch: branch)
        }
        guard let location = expandedLocation else { return .root(projectRoot, note: Self.locationNote) }
        return .create(path: freePath(in: location, suffix: taskNumber.map { String($0) } ?? Self.slug(branch)), branch: branch)
    }

    /// Runs `git worktree add` for `.create` only, into a folder it makes just before. A failure or a timeout opens the project root
    /// instead, with the reason (rule 4).
    public func materialise(_ plan: TaskFolderPlan) async -> TaskFolder {
        switch plan {
        case .existing(let url, _): return TaskFolder(url: url, note: nil, created: false)
        case .root(let url, let note): return TaskFolder(url: url, note: note, created: false)
        case .create(let path, let branch): return await addWorktree(at: path, branch: branch)
        }
    }

    private func addWorktree(at planned: URL, branch: String) async -> TaskFolder {
        // The arguments carry no "--", so git would read a leading "-" as an option: -Bmain resets main.
        guard !branch.hasPrefix("-") else { return atRoot(branch, reason: "'\(branch)' is not a valid branch name") }
        let path: URL
        switch Self.claim(planned) {
        case .success(let claimed): path = claimed
        case .failure(let failure): return atRoot(branch, reason: failure.reason)
        }
        let reason: String
        do {
            let result = try await runner.run("git", GitCommand.read(["worktree", "add", path.path, branch]),
                                              in: projectRoot, timeout: CommandTimeout.worktreeAdd)
            if result.succeeded { return TaskFolder(url: path, note: nil, created: true) }
            reason = Self.errorLine(result.stderr) ?? "git exited with status \(result.status)"
        } catch {
            reason = Self.describe(error)
        }
        // rmdir removes only an empty folder, so nothing git wrote is ever deleted.
        rmdir(path.path)
        return atRoot(branch, reason: reason)
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

    private func atRoot(_ branch: String, reason: String) -> TaskFolder {
        TaskFolder(url: projectRoot, note: "Couldn't create a worktree for \(branch), so the shell opens at the project root: \(reason)", created: false)
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

    /// `<project>-<suffix>` in the worktree location, or the first of -2, -3, … that nothing occupies.
    private func freePath(in location: URL, suffix: String) -> URL {
        let name = "\(Self.slug(projectRoot.lastPathComponent))-\(suffix)"
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
}
