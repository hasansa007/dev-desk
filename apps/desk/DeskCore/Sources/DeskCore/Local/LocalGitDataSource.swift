import Foundation

public enum LocalProjectError: Error, Equatable, LocalizedError {
    case folderMissing(String)
    public var errorDescription: String? {
        switch self {
        case .folderMissing(let path): return "The folder \(path) no longer exists."
        }
    }
}

public struct LocalGitDataSource: ProjectDataSource {
    public let root: URL
    let runner: CommandRunner

    static let notARepository = "This folder is not a git repository."
    static let insightsReason = "Insights needs a validated agent connection. None is set up, so this panel can't answer yet."
    static let maxReportBytes = 1_048_576
    static let maxStateBytes = 262_144
    static let partialCloneReason = "This is a partial clone. Dev Desk doesn't read it, because reading could fetch from its remote and run a command its configuration names."
    static let remotesUncheckedReason = "Dev Desk couldn't check this repository's remotes, so it doesn't read it."

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public func load() async throws -> ProjectSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { throw LocalProjectError.folderMissing(root.path) }
        async let info = identity()
        async let toplevel = repositoryRoot()
        async let tools = ToolDetection.detect(runner: runner)
        async let terminalCLIs = TerminalAgent.detect(runner: runner)
        let project = await info
        let top: String
        switch await toplevel {
        case .success(let path): top = path
        case .failure(let failure):
            return Self.plainFolder(project, tools: await tools, terminalCLIs: await terminalCLIs, reason: failure.detail)
        }

        let topURL = URL(fileURLWithPath: top)
        async let githubState = GitHubReader(directory: root, runner: runner).read(remote: project.remote)
        // These config reads run nothing; they must precede the branch fan-out, whose rev-list/log/diff could lazily fetch and run uploadpack.
        let refusal = try await lazyFetchRefusal()
        let facts = refusal != nil ? GitFacts(base: nil, baseRef: nil, baseShort: nil, branches: [])
            : await GitReader(root: root, runner: runner).read(toplevel: top, currentBranch: project.branch)
        let github = await githubState
        // Reports are read from the base and from report branches as well as from disk, and git is only read after the gate.
        let reportRefs = refusal != nil ? [] : Self.reportRefs(facts)
        let tree = ReportTree(root: root, runner: runner, maxBytes: Self.maxReportBytes)
        var findingsFolders: [[String: SafeFile.Read]] = []
        for folder in FindingsCleanup.folders {
            findingsFolders.append(await tree.reports(in: folder, toplevel: topURL, refs: reportRefs))
        }
        let findings = Self.findings(findingsFolders)
        let ideation = Self.ideation(await tree.reports(in: "docs/ideation", toplevel: topURL, refs: reportRefs))
        let active: (title: String?, why: String) = github.data.map { ActiveMilestone.resolve($0.milestones) } ?? (nil, github.unavailableReason ?? "")
        let localBranchNote = facts.truncatedBranchCount.map { "Showing \(GitOutput.maxBranches) of \($0) local branches." }
        let localBacklog = LocalBacklog.read(projectPath: top)
        // The stages the app itself stored (ADR 0035); a sample has no folder, so it keeps none.
        let stages = BoardStages.read(projectRoot: topURL)
        let checkpoints = Self.taskStates(facts: facts, toplevel: topURL)
        let detected = await tools
        let board: Surface<[DeskTask]>
        if let refusal {
            board = .unavailable(refusal)
        } else {
            board = .available(BoardBuilder.build(BoardInput(git: facts, currentBranch: project.branch,
                                                             github: github.data, activeMilestone: active.title,
                                                             pipeline: Self.pipelineStates(facts: facts, github: github.data, toplevel: topURL),
                                                             issuePipeline: checkpoints.issues, localPipeline: checkpoints.local,
                                                             localBacklog: localBacklog, stages: stages.stages)))
        }
        var offBase: FolderOffBase?
        if refusal == nil, let base = facts.base, let baseRef = facts.baseRef, baseRef.hasPrefix("refs/remotes/origin/"),
           !project.branch.isEmpty, project.branch != base {
            let status = try? await runner.run("git", GitCommand.read(["status", "--porcelain", "--untracked-files=no"]), in: root, timeout: CommandTimeout.git)
            let dirty = status.map { !$0.succeeded || !$0.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
            offBase = FolderOffBase(branch: project.branch, base: base, isDirty: dirty)
        }
        var snapshot = ProjectSnapshot(
            project: project, isDemo: false, board: board,
            boardNote: refusal != nil ? "" : BoardBuilder.note(github: github, activeMilestone: active, localBranchNote: localBranchNote),
            findings: .available(findings), ideation: .available(ideation),
            roadmap: Self.roadmap(github),
            connections: detected + [ToolDetection.github(github)], connectionsNote: ToolDetection.note,
            capabilities: ToolDetection.capabilities,
            insights: InsightsAgent.availability(connections: detected, repositoryRoot: top, noAgentReason: Self.insightsReason),
            projectFacts: Self.facts(base: facts.base, baseShort: facts.baseShort, remote: project.remote, active: active, github: github),
            slug: github.data?.slug, activeMilestone: active.title,
            localBacklog: localBacklog, filedBacklogKeys: LocalBacklog.filedKeys(projectPath: top), repositoryRoot: top,
            terminalAgents: await terminalCLIs)
        snapshot.folderOffBase = offBase
        snapshot.trackerUnavailable = github.data == nil ? (github.shortUnavailableReason ?? "GitHub unavailable") : nil
        snapshot.openMilestones = github.data?.milestones.map(\.title) ?? []
        return snapshot
    }

    /// A partial clone, or any promisor remote, lazy-fetches missing objects mid-read, running remote.<name>.uploadpack — even without
    /// extensions.partialClone on git before 2.44. Returns why the repo is refused, or nil only when both reads cleanly say "not set".
    private func lazyFetchRefusal() async throws -> String? {
        switch try await config(["--get", "extensions.partialClone"]) {
        case .value: return Self.partialCloneReason
        case .unknown: return Self.remotesUncheckedReason
        case .unset: break
        }
        // --type=bool applies git's own rule (any non-zero integer is true, an empty value false) and exits non-zero on a non-bool.
        switch try await config(["--type=bool", "--get-regexp", "^remote\\..*\\.promisor$"]) {
        case .value(let output):
            guard let on = GitOutput.anyPromisorIsOn(output) else { return Self.remotesUncheckedReason }
            return on ? Self.partialCloneReason : nil
        case .unknown: return Self.remotesUncheckedReason
        case .unset: return nil
        }
    }

    private enum ConfigRead { case unset, value(String), unknown }

    /// A gate read on the same hardened path as every other read. Only exit 1 with no output at all means "not set"; any other exit,
    /// a timeout or a signal (the runner reports 128+N) is .unknown. Cancellation is rethrown, so the load is dropped, not refused.
    private func config(_ arguments: [String]) async throws -> ConfigRead {
        let result: CommandResult
        do {
            result = try await runner.run("git", GitCommand.read(["config"] + arguments), in: root, timeout: CommandTimeout.git)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return .unknown
        }
        if result.succeeded { return .value(result.stdout) }
        return result.status == 1 && result.stdout.isEmpty && result.stderr.isEmpty ? .unset : .unknown
    }

    func identity() async -> ProjectInfo {
        async let branch = git(["rev-parse", "--abbrev-ref", "HEAD"])
        async let remote = git(["remote", "get-url", "origin"])
        async let head = git(["rev-parse", "--short", "HEAD"])
        return ProjectInfo(name: root.lastPathComponent, displayPath: Self.abbreviate(root.path),
                           branch: await branch ?? "", remote: await remote.map(GitRemote.display), headRevision: await head)
    }

    /// Trimmed stdout of a successful (hardened) git call; nil when git fails or is missing.
    func git(_ arguments: [String]) async -> String? {
        guard let result = try? await runner.run("git", GitCommand.read(arguments), in: root, timeout: CommandTimeout.git), result.succeeded else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Tells git missing, the command line tools missing and git's ownership refusal apart from a folder that is simply not a repository.
    static func notARepositoryReason(status: Int32, stderr: String) -> String {
        if status == 127 { return "Git is not installed, so this folder can't be read." }
        if stderr.contains("xcrun: error") || stderr.contains("xcode-select") {
            return "The Xcode command line tools are missing, so git can't run. Install them with xcode-select --install."
        }
        if stderr.contains("dubious ownership") {
            let trust = GitOutput.lines(stderr).map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("git config --global --add safe.directory") }
            return "Git refuses to read this folder because another user owns it (dubious ownership)." + (trust.map { " To trust it, run: \(Markdown.reason($0))" } ?? "")
        }
        if stderr.contains("not a git repository") { return notARepository }
        return "git could not read this folder: \(Markdown.reason(GitOutput.lastNonEmptyLine(stderr) ?? "git exited with status \(status)"))"
    }

    private func repositoryRoot() async -> Result<String, GitReadFailure> {
        do {
            let result = try await runner.run("git", GitCommand.read(["rev-parse", "--show-toplevel"]), in: root, timeout: CommandTimeout.git)
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.succeeded, !path.isEmpty else {
                return .failure(GitReadFailure(detail: Self.notARepositoryReason(status: result.status, stderr: result.stderr)))
            }
            return .success(path)
        } catch {
            var text = error.localizedDescription
            if text.hasSuffix(".") { text.removeLast() }
            return .failure(GitReadFailure(detail: "git could not read this folder: \(Markdown.reason(text))"))
        }
    }

    private static func plainFolder(_ project: ProjectInfo, tools: [Connection], terminalCLIs: [TerminalAgent],
                                    reason: String) -> ProjectSnapshot {
        let unread = reason != notARepository
        let github = GitHubState.unavailable(unread ? "git could not read this folder" : "no GitHub remote")
        return ProjectSnapshot(
            project: project, isDemo: false, board: .unavailable(reason), boardNote: "",
            findings: .unavailable(reason), ideation: .unavailable(reason),
            roadmap: .unavailable(reason),
            connections: tools + [ToolDetection.github(github)], connectionsNote: ToolDetection.note,
            capabilities: ToolDetection.capabilities,
            insights: InsightsAgent.availability(connections: tools, repositoryRoot: nil, noAgentReason: insightsReason),
            projectFacts: facts(base: nil, baseShort: nil, remote: nil,
                                active: (nil, unread ? "git could not read this folder" : "not a git repository"), github: github),
            terminalAgents: terminalCLIs)
    }

    /// Without open issues every theme would look empty, so an issue-read failure makes the roadmap unavailable rather than bare.
    private static func roadmap(_ github: GitHubState) -> Surface<Roadmap> {
        guard let data = github.data else {
            let remedy = github.unavailableRemedy.map { " \($0)" } ?? ""
            return .unavailable("GitHub is unavailable (\(github.unavailableReason ?? "")), so the roadmap can't be read.\(remedy)")
        }
        if let detail = data.issuesUnavailable { return .unavailable("Open issues could not be read (\(detail)), so the roadmap can't be read.") }
        return .available(RoadmapBuilder.build(milestones: data.milestones, issues: data.issues))
    }

    private static func facts(base: String?, baseShort: String?, remote: String?, active: (title: String?, why: String), github: GitHubState) -> [KeyValue] {
        [
            KeyValue("Base branch", base ?? "none", monospaced: true),
            KeyValue("Base revision", baseShort ?? "none", monospaced: true),
            KeyValue("Remote", remote ?? "none", monospaced: true),
            KeyValue("Active milestone", active.title ?? "none — \(active.why)"),
            KeyValue("GitHub account", github.data.map { $0.account ?? "signed in" } ?? github.unavailableReason ?? ""),
        ]
    }

    /// A branch checked out in another worktree keeps its `.dev` state there, where dev.py wrote it.
    private static func pipelineStates(facts: GitFacts, github: GitHubData?, toplevel: URL) -> [String: PipelineState] {
        let worktrees = Dictionary(facts.branches.compactMap { branch in branch.worktree.map { (branch.name, URL(fileURLWithPath: $0)) } },
                                   uniquingKeysWith: { first, _ in first })
        var states: [String: PipelineState] = [:]
        for name in Set(facts.branches.map(\.name) + (github?.openPullRequests.map(\.headRefName) ?? [])) {
            let file = ".dev/\(PipelineState.slug(name)).json"
            states[name] = [worktrees[name], toplevel].compactMap { $0 }.lazy
                .compactMap { dir -> PipelineState? in
                    guard case .text(let text) = SafeFile.read(dir.appendingPathComponent(file), maxBytes: maxStateBytes, within: dir) else { return nil }
                    return PipelineState.parse(Data(text.utf8))
                }
                .first
        }
        return states
    }

    /// `.dev/issue-N.json`, which `/dev` checkpoints under the issue rather than the branch: a feature's branch is cut
    /// after Phase 5 and a task run starts detached, so these are the only record of phases 1–8. Every worktree is
    /// read, and the furthest phase wins where two folders hold one task. `.dev/local-ID.json` is the same for a
    /// `docs/backlog/` entry, which has no issue number.
    static func taskStates(facts: GitFacts, toplevel: URL) -> (issues: [Int: PipelineState], local: [String: PipelineState]) {
        var states: [Int: PipelineState] = [:]
        var local: [String: PipelineState] = [:]
        let folders = [toplevel] + facts.worktreePaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        for folder in folders {
            let dev = folder.appendingPathComponent(".dev", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dev.path) else { continue }
            for name in names {
                let number = PipelineState.issueNumber(fileName: name)
                let entry = PipelineState.localID(fileName: name)
                guard number != nil || entry != nil,
                      case .text(let text) = SafeFile.read(dev.appendingPathComponent(name), maxBytes: maxStateBytes, within: folder),
                      let state = PipelineState.parse(Data(text.utf8)) else { continue }
                if let number, state.phase >= (states[number]?.phase ?? -1) { states[number] = state }
                if let entry, state.phase >= (local[entry]?.phase ?? -1) { local[entry] = state }
            }
        }
        return (states, local)
    }

    /// Origin's base, then every branch holding only a report, newest first.
    static func reportRefs(_ facts: GitFacts) -> [String] {
        let branches = facts.branches.filter { $0.unmerged > 0 && BoardBuilder.holdsOnlyReports($0) }
            .sorted { ($0.lastCommit ?? .distantPast) > ($1.lastCommit ?? .distantPast) }
            .map { "refs/heads/\($0.name)" }
        return (facts.baseRef.map { [$0] } ?? []) + branches
    }

    /// One map per `FindingsCleanup.folders` entry, name → contents, as `ReportTree` found them.
    static func findings(_ folders: [[String: SafeFile.Read]]) -> FindingsReport {
        var runs: [FindingsRun] = []
        var findings: [Finding] = []
        var groups: [FindingsGroup] = []
        // `docs/survey/` is where reports went before the rename (ADR 0042). A run in both folders is read once,
        // from the new one.
        let files = folders.enumerated().flatMap { rank, reports in reports.map { (name: $0.key, rank: rank, read: $0.value) } }
        var seen: Set<String> = []
        for (name, _, read) in files.sorted(by: { ($0.name, -$0.rank) > ($1.name, -$1.rank) })
        where seen.insert(name).inserted {
            let stem = String(name.dropLast(3))
            switch read {
            case .text(let text):
                runs.append(FindingsRun(id: stem, label: stem, revision: nil))
                findings.append(contentsOf: FindingsReportParser.parse(text, runID: stem))
                groups.append(contentsOf: FindingsReportParser.groups(text, runID: stem))
            case .tooLarge:
                runs.append(FindingsRun(id: stem, label: "\(stem) · Report too large to read (over 1 MB)", revision: nil))
            case .hardLink:
                runs.append(FindingsRun(id: stem, label: "\(stem) · Report not read (it is a hard link)", revision: nil))
            case .skipped:
                continue
            }
        }
        return FindingsReport(runs: runs, findings: findings, groups: groups)
    }

    static func ideation(_ reports: [String: SafeFile.Read]) -> IdeationReport {
        var runs: [IdeationRun] = []
        var opportunities: [Opportunity] = []
        for name in reports.keys.sorted(by: >) {
            let stem = String(name.dropLast(3))
            switch reports[name] ?? .skipped {
            case .text(let text):
                runs.append(IdeationRun(id: stem, label: stem, kinds: IdeationReportParser.kinds(text)))
                opportunities.append(contentsOf: IdeationReportParser.parse(text, runID: stem))
            case .tooLarge:
                runs.append(IdeationRun(id: stem, label: "\(stem) · Report too large to read (over 1 MB)"))
            case .hardLink:
                runs.append(IdeationRun(id: stem, label: "\(stem) · Report not read (it is a hard link)"))
            case .skipped:
                continue
            }
        }
        return IdeationReport(runs: runs, opportunities: opportunities)
    }
}
