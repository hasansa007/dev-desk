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

    public init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        self.runner = runner
    }

    public func load() async throws -> ProjectSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { throw LocalProjectError.folderMissing(root.path) }
        let throttled = ThrottledRunner(base: runner, limit: 6)
        async let info = identity()
        async let toplevel = git(["rev-parse", "--show-toplevel"])
        async let tools = ToolDetection.detect(runner: throttled)
        let project = await info
        guard let top = await toplevel else { return Self.plainFolder(project, tools: await tools) }

        let topURL = URL(fileURLWithPath: top)
        async let gitFacts = GitReader(root: root, runner: throttled).read(toplevel: top, currentBranch: project.branch)
        async let githubState = GitHubReader(directory: root, runner: throttled).read(remote: project.remote)
        async let findings = Self.findings(in: topURL)
        async let decisions = Self.decisions(in: topURL)
        let facts = await gitFacts
        let github = await githubState
        let active: (title: String?, why: String) = github.data.map { ActiveMilestone.resolve($0.milestones) } ?? (nil, github.unavailableReason ?? "")
        let board = BoardBuilder.build(BoardInput(git: facts, github: github.data, activeMilestone: active.title,
                                                  pipeline: Self.pipelineStates(facts: facts, github: github.data, toplevel: topURL)))
        let roadmap: Surface<Roadmap> = github.data.map { .available(RoadmapBuilder.build(milestones: $0.milestones, issues: $0.issues)) }
            ?? .unavailable("GitHub is unavailable (\(github.unavailableReason ?? "")), so the roadmap can't be read.")
        return ProjectSnapshot(
            project: project, isDemo: false, board: .available(board),
            boardNote: BoardBuilder.note(github: github, activeMilestone: active),
            findings: .available(await findings), roadmap: roadmap, decisions: .available(await decisions),
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

    /// Trimmed stdout of a successful git call; nil when git fails or is missing.
    func git(_ arguments: [String]) async -> String? {
        guard let result = try? await runner.run("git", arguments, in: root, timeout: CommandTimeout.git), result.succeeded else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func plainFolder(_ project: ProjectInfo, tools: [Connection]) -> ProjectSnapshot {
        let github = GitHubState.unavailable("no GitHub remote")
        return ProjectSnapshot(
            project: project, isDemo: false, board: .unavailable(notARepository), boardNote: "",
            findings: .unavailable(notARepository), roadmap: .unavailable(notARepository), decisions: .unavailable(notARepository),
            connections: tools + [ToolDetection.github(github)], connectionsNote: ToolDetection.note,
            capabilities: ToolDetection.capabilities, insights: .unavailable(insightsReason),
            projectFacts: facts(base: nil, baseShort: nil, remote: nil, active: (nil, "not a git repository"), github: github))
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
                .compactMap { (try? Data(contentsOf: $0.appendingPathComponent(file))).flatMap(PipelineState.parse) }
                .first
        }
        return states
    }

    private static func findings(in toplevel: URL) -> FindingsReport {
        let folder = toplevel.appendingPathComponent("docs/survey")
        let reports = markdownFiles(in: folder).sorted(by: >).compactMap { name -> (stem: String, text: String)? in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return (String(name.dropLast(3)), text)
        }
        return FindingsReport(runs: reports.map { SurveyRun(id: $0.stem, label: $0.stem, revision: nil) },
                              findings: reports.flatMap { SurveyReportParser.parse($0.text, runID: $0.stem) })
    }

    private static func decisions(in toplevel: URL) -> [Decision] {
        let folder = toplevel.appendingPathComponent("docs/adr")
        func number(_ name: String) -> Int { Int(name.prefix { $0.isASCII && $0.isNumber }) ?? -1 }
        return markdownFiles(in: folder)
            .filter { $0.lowercased() != "readme.md" }
            .sorted { (number($0), $0) > (number($1), $1) }
            .compactMap { name in
                (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)).map { ADRParser.parse($0, fileName: name) }
            }
    }

    private static func markdownFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".md") }
    }
}

/// Caps concurrent commands: each ProcessRunner call blocks up to three GCD threads, and an exhausted pool stalls pipe reads.
struct ThrottledRunner: CommandRunner {
    let base: CommandRunner
    private let gate: CommandGate

    init(base: CommandRunner, limit: Int) {
        self.base = base
        gate = CommandGate(limit: limit)
    }

    func run(_ tool: String, _ arguments: [String], in directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        await gate.acquire()
        do {
            let result = try await base.run(tool, arguments, in: directory, timeout: timeout)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }
}

private actor CommandGate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = limit }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
