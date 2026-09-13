import Foundation

struct GitHubLabel: Decodable, Equatable {
    var name: String
}

struct GitHubIssue: Decodable, Equatable {
    struct MilestoneRef: Decodable, Equatable {
        var title: String
    }

    var number: Int
    var title: String
    var labels: [GitHubLabel] = []
    var milestone: MilestoneRef? = nil
    var updatedAt: String = ""
    var body: String = ""
    var url: String = ""

    var labelNames: [String] { labels.map(\.name) }
}

struct GitHubPullRequest: Decodable, Equatable {
    var number: Int
    var title: String
    var headRefName: String = ""
    /// The head is a fork's branch, so its name says nothing about this repository's branches.
    var isCrossRepository: Bool = false
    var reviewDecision: String? = nil
    var isDraft: Bool = false
    var url: String = ""
    var body: String = ""
}

struct GitHubMergedPullRequest: Decodable, Equatable {
    var number: Int
    var title: String
    var headRefName: String = ""
    var isCrossRepository: Bool = false
    var mergedAt: String? = nil
    var url: String = ""
    /// The commit GitHub merged, so a local branch still pointing at it reads as merged.
    var headRefOid: String? = nil
}

struct GitHubMilestone: Decodable, Equatable {
    var title: String
    var dueOn: String? = nil
    var createdAt: String? = nil
    var openIssues: Int = 0
    var closedIssues: Int = 0

    enum CodingKeys: String, CodingKey {
        case title, dueOn = "due_on", createdAt = "created_at", openIssues = "open_issues", closedIssues = "closed_issues"
    }
}

struct GitHubCheck: Decodable, Equatable {
    var name: String
    var bucket: String
    var link: String? = nil
}

enum PullRequestChecks: Equatable {
    case read([GitHubCheck])
    case failed(String)
}

struct GitHubData: Equatable {
    var slug: String
    var account: String?
    var issues: [GitHubIssue] = []
    /// Why open issues could not be read while pull requests could, e.g. a fork with issues turned off.
    var issuesUnavailable: String? = nil
    var openPullRequests: [GitHubPullRequest] = []
    var mergedPullRequests: [GitHubMergedPullRequest] = []
    var milestones: [GitHubMilestone] = []
    /// Keyed by pull request number; a missing key means its checks were not read.
    var checks: [Int: PullRequestChecks] = [:]
}

enum GitHubState: Equatable {
    case ready(GitHubData)
    case unavailable(String)

    var data: GitHubData? {
        if case .ready(let data) = self { return data }
        return nil
    }

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    /// The reason in three words. The full sentence is a GraphQL error with a repository path in it, and a
    /// sidebar row rendering it whole turned the connection into a red wall of text — the detail belongs in
    /// the tooltip, not in the row.
    var shortUnavailableReason: String? {
        guard let reason = unavailableReason else { return nil }
        if reason.contains("Could not resolve to a Repository") { return "repository not found" }
        if reason.contains("gh not installed") { return "gh not installed" }
        if reason.lowercased().contains("auth") || reason.contains("not logged") { return "not signed in" }
        return reason.count > 40 ? "unavailable" : reason
    }

    /// What to do about it, when the reason says something actionable. A GraphQL error pasted at the developer
    /// names a failure without naming a fix, and the commonest cause here is a remote pointing at a repository
    /// this account can no longer see — a deleted fork, a take-home repo, an org you left.
    var unavailableRemedy: String? {
        guard let reason = unavailableReason else { return nil }
        if reason.contains("Could not resolve to a Repository") {
            return "The remote points at a repository this GitHub account cannot see — it may have been deleted, "
                + "made private, or your access removed. Point origin at a repository you own "
                + "(`git remote set-url origin …`), or sign in as an account that can see this one (`gh auth login`)."
        }
        if reason.contains("gh not installed") {
            return "Install the GitHub CLI (`brew install gh`), then `gh auth login`."
        }
        if reason.lowercased().contains("auth") || reason.contains("not logged") {
            return "Run `gh auth login`, then reload."
        }
        return nil
    }
}

/// Pure decoding of gh output.
enum GitHubJSON {
    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(text.utf8))
    }

    /// Reads "Logged in to github.com account NAME" (gh 2.40+) or the older "… as NAME".
    static func account(fromAuthStatus text: String) -> String? {
        let pattern = try! Regex(#"Logged in to github\.com (?:account|as) (\S+)"#)
        return text.firstMatch(of: pattern)?.output[1].substring.map(String.init)
    }

    static func authFailureReason(_ output: String) -> String {
        output.contains("Timeout trying to log in") ? "gh could not reach github.com" : "not signed in to GitHub"
    }

    /// gh exits 8 while checks are pending, so JSON is trusted whatever the status; only "no checks reported" is a genuine empty list.
    static func checks(from result: CommandResult) -> PullRequestChecks {
        if let checks = decode([GitHubCheck].self, from: result.stdout) { return .read(checks) }
        if result.stderr.contains("no checks reported") { return .read([]) }
        if result.succeeded { return .failed("gh returned unreadable output") }
        return .failed(Markdown.reason(GitOutput.lastNonEmptyLine(result.stderr) ?? "gh exited with status \(result.status)"))
    }
}

private struct GitHubReadFailure: Error {
    let what: String
    let detail: String

    var reason: String { "could not read \(what): \(detail)" }
}

struct GitHubReader {
    static let checkedPullRequests = 10

    let directory: URL
    let runner: CommandRunner

    /// `remote` is the origin URL in any form GitRemote accepts; nil when the repository has none.
    func read(remote: String?) async -> GitHubState {
        guard let remote else { return .unavailable("no GitHub remote") }
        guard let slug = GitRemote.githubSlug(remote) else { return .unavailable("the remote is not on GitHub") }
        let auth: CommandResult
        do {
            auth = try await authStatus()
        } catch {
            return .unavailable("gh could not run: \(Self.describe(error))")
        }
        if auth.toolMissing { return .unavailable("gh not installed") }
        let status = auth.stdout + "\n" + auth.stderr
        // authFailureReason returns fixed prose, so the account name in `status` never reaches a reason.
        guard auth.succeeded else { return .unavailable(GitHubJSON.authFailureReason(status)) }

        var data = GitHubData(slug: slug, account: GitHubJSON.account(fromAuthStatus: status))
        async let issues = list([GitHubIssue].self, "open issues",
                                ["issue", "list", "--repo", slug, "--state", "open", "--limit", "200", "--json", "number,title,labels,milestone,updatedAt,body,url"])
        async let open = list([GitHubPullRequest].self, "open pull requests",
                              ["pr", "list", "--repo", slug, "--state", "open", "--limit", "100", "--json",
                               "number,title,headRefName,isCrossRepository,reviewDecision,isDraft,url,body"])
        async let merged = list([GitHubMergedPullRequest].self, "merged pull requests",
                                ["pr", "list", "--repo", slug, "--state", "merged", "--limit", "10", "--json", "number,title,headRefName,isCrossRepository,mergedAt,url,headRefOid"])
        async let milestones = list([GitHubMilestone].self, "milestones", ["api", "repos/\(slug)/milestones?state=open"])
        do {
            data.issues = try await issues
        } catch {
            data.issuesUnavailable = (error as? GitHubReadFailure)?.detail ?? Self.describe(error)
        }
        do {
            data.openPullRequests = try await open
            data.mergedPullRequests = try await merged
            data.milestones = try await milestones
        } catch {
            return .unavailable((error as? GitHubReadFailure)?.reason ?? Self.describe(error))
        }
        let numbers = data.openPullRequests.prefix(Self.checkedPullRequests).map(\.number)
        let checks = await numbers.concurrentMap { number in (number, await pullRequestChecks(number, slug: slug)) }
        data.checks = Dictionary(checks, uniquingKeysWith: { first, _ in first })
        return .ready(data)
    }

    /// Asks about the active account only, so a broken inactive account cannot report a working user as signed out; older gh lacks --active.
    private func authStatus() async throws -> CommandResult {
        let active = try await gh(["auth", "status", "--active", "--hostname", "github.com"])
        guard !active.succeeded, active.stderr.contains("unknown flag: --active") else { return active }
        return try await gh(["auth", "status", "--hostname", "github.com"])
    }

    private func list<T: Decodable>(_ type: T.Type, _ what: String, _ arguments: [String]) async throws -> T {
        let result: CommandResult
        do {
            result = try await gh(arguments)
        } catch {
            throw GitHubReadFailure(what: what, detail: Self.describe(error))
        }
        guard result.succeeded else {
            throw GitHubReadFailure(what: what, detail: Markdown.reason(GitOutput.lastNonEmptyLine(result.stderr) ?? "gh exited with status \(result.status)"))
        }
        guard let value = GitHubJSON.decode(type, from: result.stdout) else {
            throw GitHubReadFailure(what: what, detail: "gh returned unreadable JSON")
        }
        return value
    }

    private func pullRequestChecks(_ number: Int, slug: String) async -> PullRequestChecks {
        do {
            return GitHubJSON.checks(from: try await gh(["pr", "checks", String(number), "--repo", slug, "--json", "name,bucket,link"]))
        } catch {
            return .failed(Self.describe(error))
        }
    }

    private func gh(_ arguments: [String]) async throws -> CommandResult {
        try await runner.run("gh", arguments, in: directory, timeout: CommandTimeout.gh)
    }

    /// A thrown error's message, escaped because it becomes a markdown-rendered GitHub reason.
    private static func describe(_ error: Error) -> String {
        var text = error.localizedDescription
        if text.hasSuffix(".") { text.removeLast() }
        return Markdown.reason(text)
    }
}
