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

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public func load() async throws -> ProjectSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { throw LocalProjectError.folderMissing(root.path) }
        async let info = identity()
        async let toplevel = repositoryRoot()
        async let tools = ToolDetection.detect(runner: runner)
        let project = await info
        let top: String
        switch await toplevel {
        case .success(let path): top = path
        case .failure(let failure): return Self.plainFolder(project, tools: await tools, reason: failure.detail)
        }

        let topURL = URL(fileURLWithPath: top)
        async let gitFacts = GitReader(root: root, runner: runner).read(toplevel: top, currentBranch: project.branch)
        async let githubState = GitHubReader(directory: root, runner: runner).read(remote: project.remote)
        async let findings = Self.findings(in: topURL)
        async let decisions = Self.decisions(in: topURL)
        let facts = await gitFacts
        let github = await githubState
        let active: (title: String?, why: String) = github.data.map { ActiveMilestone.resolve($0.milestones) } ?? (nil, github.unavailableReason ?? "")
        let board = BoardBuilder.build(BoardInput(git: facts, github: github.data, activeMilestone: active.title,
                                                  pipeline: Self.pipelineStates(facts: facts, github: github.data, toplevel: topURL)))
        let localBranchNote = facts.truncatedBranchCount.map { "Showing \(GitOutput.maxBranches) of \($0) local branches." }
        return ProjectSnapshot(
            project: project, isDemo: false, board: .available(board),
            boardNote: BoardBuilder.note(github: github, activeMilestone: active, localBranchNote: localBranchNote),
            findings: .available(await findings), roadmap: Self.roadmap(github), decisions: .available(await decisions),
            connections: await tools + [ToolDetection.github(github)], connectionsNote: ToolDetection.note,
            capabilities: ToolDetection.capabilities, insights: .unavailable(Self.insightsReason),
            projectFacts: Self.facts(base: facts.base, baseShort: facts.baseShort, remote: project.remote, active: active, github: github))
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
            return "Git refuses to read this folder because another user owns it (dubious ownership)." + (trust.map { " To trust it, run: \($0)" } ?? "")
        }
        if stderr.contains("not a git repository") { return notARepository }
        return "git could not read this folder: \(GitOutput.lastNonEmptyLine(stderr) ?? "git exited with status \(status)")"
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
            return .failure(GitReadFailure(detail: "git could not read this folder: \(text)"))
        }
    }

    private static func plainFolder(_ project: ProjectInfo, tools: [Connection], reason: String) -> ProjectSnapshot {
        let unread = reason != notARepository
        let github = GitHubState.unavailable(unread ? "git could not read this folder" : "no GitHub remote")
        return ProjectSnapshot(
            project: project, isDemo: false, board: .unavailable(reason), boardNote: "",
            findings: .unavailable(reason), roadmap: .unavailable(reason), decisions: .unavailable(reason),
            connections: tools + [ToolDetection.github(github)], connectionsNote: ToolDetection.note,
            capabilities: ToolDetection.capabilities, insights: .unavailable(insightsReason),
            projectFacts: facts(base: nil, baseShort: nil, remote: nil,
                                active: (nil, unread ? "git could not read this folder" : "not a git repository"), github: github))
    }

    /// Without open issues every theme would look empty, so an issue-read failure makes the roadmap unavailable rather than bare.
    private static func roadmap(_ github: GitHubState) -> Surface<Roadmap> {
        guard let data = github.data else { return .unavailable("GitHub is unavailable (\(github.unavailableReason ?? "")), so the roadmap can't be read.") }
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

    private static func findings(in toplevel: URL) -> FindingsReport {
        let folder = toplevel.appendingPathComponent("docs/survey")
        var runs: [SurveyRun] = []
        var findings: [Finding] = []
        for name in markdownFiles(in: folder).sorted(by: >) {
            let stem = String(name.dropLast(3))
            switch SafeFile.read(folder.appendingPathComponent(name), maxBytes: maxReportBytes, within: toplevel) {
            case .text(let text):
                runs.append(SurveyRun(id: stem, label: stem, revision: nil))
                findings.append(contentsOf: SurveyReportParser.parse(text, runID: stem))
            case .tooLarge:
                runs.append(SurveyRun(id: stem, label: "\(stem) · Report too large to read (over 1 MB)", revision: nil))
            case .skipped:
                continue
            }
        }
        return FindingsReport(runs: runs, findings: findings)
    }

    private static func decisions(in toplevel: URL) -> [Decision] {
        let folder = toplevel.appendingPathComponent("docs/adr")
        func number(_ name: String) -> Int { Int(name.prefix { $0.isASCII && $0.isNumber }) ?? -1 }
        return markdownFiles(in: folder)
            .filter { $0.lowercased() != "readme.md" }
            .sorted { (number($0), $0) > (number($1), $1) }
            .compactMap { name -> Decision? in
                guard case .text(let text) = SafeFile.read(folder.appendingPathComponent(name), maxBytes: maxReportBytes, within: toplevel) else { return nil }
                return ADRParser.parse(text, fileName: name)
            }
    }

    private static func markdownFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".md") }
    }
}
