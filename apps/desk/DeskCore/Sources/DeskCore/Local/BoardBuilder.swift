import Foundation

struct BoardInput {
    var git: GitFacts?
    var github: GitHubData?
    var activeMilestone: String?
    var pipeline: [String: PipelineState] = [:]
    var now: Date = Date()
    var timeZone: TimeZone = .current
}

/// Pure: git and GitHub facts in, tasks out. Columns mirror scripts/dev.py (`classify`, `build_board`, `order_next`).
enum BoardBuilder {
    static let agentsNote = "No managed sessions. Dev Desk doesn't start agents yet."
    static let checksLimitation = "CI results reported by GitHub for this pull request. Dev Desk has not verified behaviour in a running app."
    static let unlinkedRequirements = "No linked issue. Name the branch gh-<number>-… to link one."
    static let checksNotRead = "Checks are read for the \(GitHubReader.checkedPullRequests) newest open pull requests; this one was not read."

    private static let taskLine = try! Regex(#"^[ \t]*[-*][ \t]*\[([ xX])\][ \t]*#(\d+)"#)
    private static let criterion = try! Regex(#"^\s*[-*]\s*\[( |x|X)\]\s*(.+)$"#)
    private static let slice = try! Regex(#"\bslice[ \t]+(\d+)\b"#).ignoresCase().wordBoundaryKind(.simple)
    private static let closing = try! Regex(#"\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#(\d+)\b"#).ignoresCase().wordBoundaryKind(.simple)
    private static let blockedBy = try! Regex(#"\b(blocked by|depends on)\s+#(\d+)"#).ignoresCase().wordBoundaryKind(.simple)
    private static let blocks = try! Regex(#"\bblocks\s+#(\d+)"#).ignoresCase().wordBoundaryKind(.simple)

    static func build(_ input: BoardInput) -> [DeskTask] {
        BoardContext(input).tasks()
    }

    static let dockCaption = "Agents & Terminals · a shell in this task's folder"

    /// A real task's dock: a shell in the task's folder, and an Agents tab saying agents don't start from here yet.
    static func dock(taskNumber: Int?) -> DockContent {
        let example = taskNumber.map { "claude \"/dev #\($0)\"" } ?? "claude \"/dev\""
        return DockContent(tabs: [
            DockTab(id: "shell", title: "Shell", kind: .liveShell),
            DockTab(id: "agents", title: "Agents", kind: .unavailable(reason: "Dev Desk doesn't start agents yet. You can run one in the Shell tab, "
                                                                      + "for example \(example). Starting agents from here, by hand or automatically, comes next.")),
        ], caption: dockCaption)
    }

    static func note(github: GitHubState, activeMilestone: (title: String?, why: String), localBranchNote: String? = nil) -> String {
        let suffix = localBranchNote.map { " \($0)" } ?? ""
        guard let data = github.data else {
            return "GitHub is unavailable (\(github.unavailableReason ?? "")), so only local branches are shown." + suffix
        }
        let rule = "Columns follow dev:kanban's rules: git decides In progress and Review, and the active milestone decides Queued."
        let milestone = activeMilestone.title.map { " Active milestone: \($0), \(activeMilestone.why)." } ?? " No active milestone, so Queued is empty."
        let issues = data.issuesUnavailable.map { " Open issues could not be read (\($0)), so only pull requests and branches are shown." } ?? ""
        return rule + milestone + issues + suffix
    }

    /// dev.py's `^(gh-)?N(-|$)` or `/N-`.
    static func branch(_ name: String, matches number: Int) -> Bool {
        let digits = String(number)
        let rest = GitOutput.dropping("gh-", from: name)
        if rest.hasPrefix(digits) {
            let after = rest.dropFirst(digits.count)
            if after.isEmpty || after.hasPrefix("-") { return true }
        }
        return name.contains("/\(digits)-")
    }

    /// dev.py's is_startable: an epic whose checklist still has an open child is already decomposed.
    static func isDecomposedEpic(_ issue: GitHubIssue) -> Bool {
        issue.labelNames.contains("epic")
            && GitOutput.lines(issue.body).contains { $0.prefixMatch(of: taskLine)?.output[1].substring == " " }
    }

    static func priorityRank(_ issue: GitHubIssue) -> Int {
        issue.labelNames.lazy.compactMap { ["P1": 1, "P2": 2, "P3": 3][$0] }.first ?? 4
    }

    static func sliceRank(_ issue: GitHubIssue) -> Int {
        issue.title.firstMatch(of: slice)?.output[1].substring.flatMap { Int($0) } ?? 9999
    }

    static func closedIssues(_ body: String) -> Set<Int> {
        Set(body.matches(of: closing).compactMap { $0.output[3].substring.flatMap { Int($0) } })
    }

    static func reviewBadge(_ pullRequest: GitHubPullRequest) -> StatusBadge {
        if pullRequest.isDraft { return StatusBadge(.neutral, "Draft") }
        switch pullRequest.reviewDecision {
        case "CHANGES_REQUESTED": return StatusBadge(.failed, "Changes requested")
        case "APPROVED": return StatusBadge(.running, "Approved")
        case "REVIEW_REQUIRED": return StatusBadge(.info, "Review requested")
        default: return StatusBadge(.info, "PR open")
        }
    }

    static func aheadBadge(_ count: Int) -> StatusBadge {
        StatusBadge(.neutral, "\(count) commit\(count == 1 ? "" : "s") ahead")
    }

    static func outcome(ofBucket bucket: String) -> (CheckOutcome, String) {
        switch bucket {
        case "pass": return (.passed, "passed")
        case "fail": return (.failed, "failed")
        case "pending": return (.warning, "pending")
        default: return (.warning, bucket)
        }
    }

    static func requirements(body: String, title: String, source: String) -> Requirements {
        Requirements(goal: goal(in: body) ?? title, criteria: criteria(in: body), sources: source, body: body)
    }

    /// The first paragraph that is prose rather than a heading, list, table or quote.
    static func goal(in body: String) -> String? {
        var paragraph: [String] = []
        for line in GitOutput.lines(body) + [""] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                paragraph.append(trimmed)
                continue
            }
            if let first = paragraph.first, !["#", "-", "*", "|", ">"].contains(where: { first.hasPrefix($0) }) {
                return paragraph.joined(separator: " ")
            }
            paragraph = []
        }
        return nil
    }

    static func criteria(in body: String) -> [AcceptanceCriterion] {
        GitOutput.lines(body).compactMap { line in
            guard let match = line.wholeMatch(of: criterion),
                  let mark = match.output[1].substring, let text = match.output[2].substring else { return nil }
            return AcceptanceCriterion(String(text), isMet: mark != " ")
        }
    }

    static func dependencies(_ body: String) -> [Dependency] {
        let blockers = body.matches(of: blockedBy).compactMap { $0.output[2].substring.map { ("Blocked by", String($0)) } }
        let blocked = body.matches(of: blocks).compactMap { $0.output[1].substring.map { ("Blocks", String($0)) } }
        var seen = Set<String>()
        return (blockers + blocked).compactMap { verb, number in
            guard seen.insert("\(verb) \(number)").inserted else { return nil }
            return Dependency(text: "\(verb) [#\(number)](desk://task/\(number))", taskID: number)
        }
    }

    static func displayPath(_ path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
    }
}

private struct BoardContext {
    let input: BoardInput
    let branches: [BranchFacts]
    let branchByName: [String: BranchFacts]
    let openPullRequests: [GitHubPullRequest]
    let closedByPullRequest: [Int: Set<Int>]
    let calendar: Calendar
    let clock: DateFormatter
    let day: DateFormatter
    let iso8601 = ISO8601DateFormatter()

    init(_ input: BoardInput) {
        self.input = input
        branches = input.git?.branches ?? []
        branchByName = Dictionary(branches.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        openPullRequests = input.github?.openPullRequests ?? []
        closedByPullRequest = Dictionary(openPullRequests.map { ($0.number, BoardBuilder.closedIssues($0.body)) },
                                         uniquingKeysWith: { first, _ in first })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        self.calendar = calendar
        clock = Self.formatter("HH:mm", input.timeZone)
        day = Self.formatter("d MMM", input.timeZone)
    }

    func tasks() -> [DeskTask] {
        var claimedBranches = Set<String>()
        var claimedPullRequests = Set<Int>()
        var active: [DeskTask] = []
        var backlog: [(issue: GitHubIssue, task: DeskTask)] = []
        var deferred: [DeskTask] = []
        for issue in input.github?.issues ?? [] {
            let branch = branches.first { BoardBuilder.branch($0.name, matches: issue.number) }
            let pullRequest = branch.flatMap { matched in openPullRequests.first { $0.headRefName == matched.name } }
                ?? openPullRequests.first { closedByPullRequest[$0.number]?.contains(issue.number) == true }
            if let branch { claimedBranches.insert(branch.name) }
            if let pullRequest { claimedPullRequests.insert(pullRequest.number) }
            let isDeferred = issue.labelNames.contains("epic-leftover")
            let column = column(for: issue, isDeferred: isDeferred, pullRequest: pullRequest, branch: branch)
            if column == .backlog, !isDeferred, BoardBuilder.isDecomposedEpic(issue) { continue }
            let task = issueTask(issue, column: column, isDeferred: isDeferred, branch: branch, pullRequest: pullRequest)
            if isDeferred {
                deferred.append(task)
            } else if column == .backlog {
                backlog.append((issue, task))
            } else {
                active.append(task)
            }
        }
        let heads = Set(openPullRequests.map(\.headRefName))
        let pullRequestTasks = openPullRequests.filter { !claimedPullRequests.contains($0.number) }.map(pullRequestTask)
        let branchTasks = branches.filter { $0.unmerged > 0 && !claimedBranches.contains($0.name) && !heads.contains($0.name) }.map(branchTask)
        let merged = (input.github?.mergedPullRequests ?? []).map(mergedTask)
        return (active + pullRequestTasks + branchTasks + orderNext(backlog) + deferred + merged).map { task in
            var task = task
            task.dock = BoardBuilder.dock(taskNumber: task.taskNumber)
            return task
        }
    }

    /// dev.py's classify; its PR OPEN and HUMAN REVIEW columns both land in Review.
    private func column(for issue: GitHubIssue, isDeferred: Bool, pullRequest: GitHubPullRequest?, branch: BranchFacts?) -> BoardColumn {
        if isDeferred { return .backlog }
        if pullRequest != nil { return .review }
        if (branch?.unmerged ?? 0) > 0 { return .inProgress }
        if let active = input.activeMilestone, issue.milestone?.title == active { return .queued }
        return .backlog
    }

    /// dev.py's order_next: priority, then slice, then the issue ignored longest, then number.
    private func orderNext(_ rows: [(issue: GitHubIssue, task: DeskTask)]) -> [DeskTask] {
        func key(_ issue: GitHubIssue) -> (Int, Int, String, Int) {
            (BoardBuilder.priorityRank(issue), BoardBuilder.sliceRank(issue), issue.updatedAt, issue.number)
        }
        return rows.sorted { key($0.issue) < key($1.issue) }.map(\.task)
    }

    private func issueTask(_ issue: GitHubIssue, column: BoardColumn, isDeferred: Bool, branch: BranchFacts?, pullRequest: GitHubPullRequest?) -> DeskTask {
        let local = branch ?? pullRequest.flatMap { branchByName[$0.headRefName] }
        let head = local?.name ?? pullRequest?.headRefName
        let state = head.flatMap { input.pipeline[$0] }
        let badge: StatusBadge?
        if isDeferred {
            badge = StatusBadge(.neutral, "Deferred")
        } else if let pullRequest {
            badge = BoardBuilder.reviewBadge(pullRequest)
        } else if column == .inProgress, let local {
            badge = BoardBuilder.aheadBadge(local.unmerged)
        } else {
            badge = nil
        }
        return DeskTask(
            id: String(issue.number), issueNumber: issue.number, title: issue.title, column: column,
            cardBadge: badge, cardNote: state?.cardNote,
            headerBadge: badge ?? StatusBadge(.neutral, column == .queued ? "Queued" : "Backlog"),
            branchLine: branchLine(head, local: local), parallelLine: parallelLine(head, local: local),
            branch: head,
            nextAction: nextAction(local: local, pullRequestURL: pullRequest?.url, issueURL: issue.url),
            pipeline: state?.progress,
            activity: activity(head, local: local),
            requirements: .available(BoardBuilder.requirements(body: issue.body, title: issue.title, source: "Issue #\(issue.number)")),
            changes: changes(head, local: local),
            evidence: evidence(pullRequest: pullRequest?.number, state: state),
            agentsNote: BoardBuilder.agentsNote,
            dependencies: BoardBuilder.dependencies(issue.body),
            parallel: parallel(head, local: local))
    }

    private func pullRequestTask(_ pullRequest: GitHubPullRequest) -> DeskTask {
        let head = pullRequest.headRefName.isEmpty ? nil : pullRequest.headRefName
        let local = head.flatMap { branchByName[$0] }
        let state = head.flatMap { input.pipeline[$0] }
        let badge = BoardBuilder.reviewBadge(pullRequest)
        return DeskTask(
            id: "pr:\(pullRequest.number)", title: pullRequest.title, column: .review,
            cardMeta: "PR #\(pullRequest.number)", cardBadge: badge, cardNote: state?.cardNote, headerBadge: badge,
            branchLine: branchLine(head, local: local), parallelLine: parallelLine(head, local: local),
            branch: head,
            nextAction: nextAction(local: local, pullRequestURL: pullRequest.url, issueURL: nil),
            pipeline: state?.progress,
            activity: activity(head, local: local),
            requirements: .available(BoardBuilder.requirements(body: pullRequest.body, title: pullRequest.title,
                                                               source: "Pull request #\(pullRequest.number)")),
            changes: changes(head, local: local),
            evidence: evidence(pullRequest: pullRequest.number, state: state),
            agentsNote: BoardBuilder.agentsNote,
            dependencies: BoardBuilder.dependencies(pullRequest.body),
            parallel: parallel(head, local: local))
    }

    private func branchTask(_ branch: BranchFacts) -> DeskTask {
        let state = input.pipeline[branch.name]
        let badge = BoardBuilder.aheadBadge(branch.unmerged)
        return DeskTask(
            id: "branch:\(branch.name)", title: branch.name, column: .inProgress,
            cardBadge: badge, cardNote: state?.cardNote, headerBadge: badge,
            branchLine: branchLine(branch.name, local: branch), parallelLine: parallelLine(branch.name, local: branch),
            branch: branch.name,
            nextAction: .reviewChanges,
            pipeline: state?.progress,
            activity: activity(branch.name, local: branch),
            requirements: .unavailable(BoardBuilder.unlinkedRequirements),
            changes: changes(branch.name, local: branch),
            evidence: evidence(pullRequest: nil, state: state),
            agentsNote: BoardBuilder.agentsNote,
            parallel: parallel(branch.name, local: branch))
    }

    private func mergedTask(_ pullRequest: GitHubMergedPullRequest) -> DeskTask {
        let day = pullRequest.mergedAt.map { String($0.prefix(10)) }
        let reason = (day.map { "Merged on \($0)." } ?? "Merged.")
            + " Dev Desk reads only open work; open the pull request for its description, commits, diff and checks."
        return DeskTask(
            id: "merged:\(pullRequest.number)", issueNumber: pullRequest.number, title: pullRequest.title, column: .done,
            cardMeta: "merged", isDimmed: true, headerBadge: StatusBadge(.ended, "Merged"),
            branchLine: [pullRequest.headRefName, day.map { "merged \($0)" } ?? "merged"].filter { !$0.isEmpty }.joined(separator: " · "),
            branch: pullRequest.headRefName.isEmpty ? nil : pullRequest.headRefName,
            nextAction: URL(string: pullRequest.url).map { .openURL($0, title: "Open pull request") },
            activity: .unavailable(reason),
            requirements: .unavailable(reason),
            changes: .unavailable(reason),
            evidence: .unavailable(reason),
            agentsNote: BoardBuilder.agentsNote,
            parallel: .none("Merged"))
    }

    private func branchLine(_ head: String?, local: BranchFacts?) -> String {
        guard let head else { return "No branch yet" }
        var parts = [head]
        if let base = input.git?.base { parts.append("base \(base)" + (input.git?.baseShort.map { "@\($0)" } ?? "")) }
        if let path = local?.worktree { parts.append("worktree \(LocalGitDataSource.abbreviate(path))") }
        return parts.joined(separator: " · ")
    }

    private func parallelLine(_ head: String?, local: BranchFacts?) -> String {
        guard let head else { return "" }
        return ([head] + [local?.worktree.map(LocalGitDataSource.abbreviate)].compactMap { $0 }).joined(separator: " · ")
    }

    private func nextAction(local: BranchFacts?, pullRequestURL: String?, issueURL: String?) -> NextAction? {
        if let local, local.unmerged > 0 { return .reviewChanges }
        if let url = pullRequestURL.flatMap(URL.init(string:)) { return .openURL(url, title: "Open pull request") }
        if let url = issueURL.flatMap(URL.init(string:)) { return .openURL(url, title: "Open on GitHub") }
        return nil
    }

    private func activity(_ head: String?, local: BranchFacts?) -> Surface<[ActivityEvent]> {
        if let failure = local?.logFailure { return .unavailable("git log failed: \(failure)") }
        if let local { return .available(activityEvents(local.commits)) }
        if let head { return .unavailable("The branch \(Markdown.escape(head)) is not in this checkout. Fetch it to see its commits.") }
        return .available([])
    }

    private func parallel(_ head: String?, local: BranchFacts?) -> ParallelPreview {
        if let failure = local?.logFailure { return .none("git log failed: \(failure)") }
        if let local { return .activity(Array(activityEvents(local.commits).prefix(5))) }
        return .none(head == nil ? "No branch yet" : "The branch isn't in this checkout")
    }

    private func changes(_ head: String?, local: BranchFacts?) -> Surface<ChangeSet> {
        if let failure = local?.diffFailure { return .unavailable("git diff failed: \(failure)") }
        if let local {
            let files = local.files.map {
                ChangedFile(id: $0.path, displayPath: BoardBuilder.displayPath($0.path), additions: $0.additions, deletions: $0.deletions)
            }
            return .available(ChangeSet(files: files, baseNote: baseNote, diffs: local.diffs))
        }
        if let head { return .unavailable("The branch \(Markdown.escape(head)) is not in this checkout. Fetch it to see its diff.") }
        return .available(ChangeSet(files: [], baseNote: "No branch yet."))
    }

    private var baseNote: String {
        guard let base = input.git?.base else { return "No base branch could be resolved." }
        // The base can be an attacker-named branch, so it is escaped rather than code-spanned; the revision is git's own hex.
        return "Diff is against \(Markdown.escape(base))" + (input.git?.baseShort.map { " at `\($0)`" } ?? "") + "."
    }

    private func evidence(pullRequest number: Int?, state: PipelineState?) -> Surface<Evidence> {
        var checks: [CheckResult] = []
        if let number {
            switch input.github?.checks[number] {
            case nil:
                return .unavailable(BoardBuilder.checksNotRead)
            case .failed(let detail)?:
                return .unavailable("gh pr checks failed: \(detail)")
            case .read(let read)?:
                checks = read.enumerated().map { index, check in
                    let (outcome, label) = BoardBuilder.outcome(ofBucket: check.bucket)
                    return CheckResult(id: "pr\(number)-\(index)", name: check.name, outcome: outcome, outcomeLabel: label, revisionLabel: "PR #\(number)")
                }
            }
        }
        let limitations = checks.isEmpty ? nil : BoardBuilder.checksLimitation
        if let state { checks.append(state.check) }
        return .available(Evidence(isDemo: false, checks: checks, limitations: limitations))
    }

    private func activityEvents(_ commits: [GitCommit]) -> [ActivityEvent] {
        commits.map { commit in
            let subject = Markdown.escape(commit.subject)
            return ActivityEvent(id: commit.sha, time: time(commit.date),
                                 text: "**\(Markdown.escape(commit.author))**" + (subject.isEmpty ? "" : " \(subject)"),
                                 detail: ToolDetail(title: "Commit \(commit.sha)", lines: [commit.date]))
        }
    }

    private func time(_ iso: String) -> String {
        guard let date = iso8601.date(from: iso) else { return String(iso.prefix(10)) }
        return (calendar.isDate(date, inSameDayAs: input.now) ? clock : day).string(from: date)
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
