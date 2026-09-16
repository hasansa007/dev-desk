import Foundation

struct BoardInput {
    var git: GitFacts?
    /// The branch this project has checked out. It is where you are, not something to pick up: the window's
    /// own title already names it, and every action a card offers is either impossible (git refuses to delete
    /// a checked-out branch) or already true (open a terminal here — you are here).
    var currentBranch: String?
    var github: GitHubData?
    var activeMilestone: String?
    var pipeline: [String: PipelineState] = [:]
    /// Entries in `docs/backlog/`. They sit in Backlog after the tracker's own, marked as local (ADR 0027).
    var localBacklog: [BacklogItem] = []
    /// Stored stages from `.devdesk/board.json`, keyed by `DeskTask.id` (ADR 0035). Consulted only
    /// after every git rule has declined, so a stage can never contradict what git says.
    var stages: [String: BoardStage] = [:]
    var now: Date = Date()
    var timeZone: TimeZone = .current
}

/// Pure: git and GitHub facts in, tasks out. The active columns still mirror scripts/dev.py (`classify`,
/// `build_board`, `order_next`); Ready for dev and the stored stages are Dev Desk's own (ADR 0035), a
/// divergence `dev board` deliberately does not follow.
enum BoardBuilder {
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

    static let dockCaption = "Agents & Terminals · your shell and the task's agent, in the task's folder"
    static let forkNote = "This pull request comes from a fork, so its branch isn't in this repository. The shell opens at the project root."
    /// Why a Queued card sits where it does (ADR 0035): a Start was made with every agent slot busy. A
    /// pipeline note of the card's own still wins — it describes the work, which says more than the wait.
    static let queuedNote = "Waiting for a free agent slot"


    static func note(github: GitHubState, activeMilestone: (title: String?, why: String), localBranchNote: String? = nil) -> String {
        let suffix = localBranchNote.map { " \($0)" } ?? ""
        guard let data = github.data else {
            let remedy = github.unavailableRemedy.map { " \($0)" } ?? ""
            return "GitHub is unavailable (\(github.unavailableReason ?? "")), so the board shows local branches and docs/backlog/.\(remedy)" + suffix
        }
        let rule = "Git decides In progress, Review and Done; the active milestone puts an issue in Ready for dev. "
            + "Ready for dev, Queued and a started card's In progress are recorded in .devdesk/board.json until git sees a commit."
        let milestone = activeMilestone.title.map { " Active milestone: \($0), \(activeMilestone.why)." } ?? " No active milestone, so only moves made here fill Ready for dev."
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
        let mergedPullRequests = input.github?.mergedPullRequests ?? []
        // A squash merge leaves a branch's own commits outside the base, so a branch still at a merged head is that merge, not new work.
        let mergedHeads = Set(mergedPullRequests.compactMap(\.headRefOid))
        let pullRequestTasks = openPullRequests.filter { !claimedPullRequests.contains($0.number) }.map(pullRequestTask)
        let branchTasks = branches.filter { branch in
            branch.unmerged > 0 && !claimedBranches.contains(branch.name) && !heads.contains(branch.name)
                && !(branch.head.map(mergedHeads.contains) ?? false)
                && branch.name != input.currentBranch
        }.map(branchTask)
        let merged = mergedPullRequests.map(mergedTask)
        // An entry that already names its issue is waiting to be moved to filed/; the issue is the card.
        let local = input.localBacklog.filter { $0.issue == nil }.map(localTask)
        return (active + pullRequestTasks + branchTasks + orderNext(backlog) + local + deferred + merged).map { task in
            var task = task
            task.baseRef = input.git?.baseRef
            task.baseShort = input.git?.baseShort
            return task
        }
    }

    /// dev.py's classify, then the lifecycle git cannot see (ADR 0035). Git's rules come first, so a
    /// stored stage can only ever fill the gap before the first commit, never override a fact.
    private func column(for issue: GitHubIssue, isDeferred: Bool, pullRequest: GitHubPullRequest?, branch: BranchFacts?) -> BoardColumn {
        if isDeferred { return .backlog }
        // A draft pull request is still being worked on — which is what makes Review → In progress a
        // real move: converting the PR back to a draft puts the card back where the work is.
        if let pullRequest { return pullRequest.isDraft ? .inProgress : .review }
        if (branch?.unmerged ?? 0) > 0 { return .inProgress }
        if let stage = stage(for: String(issue.number)) {
            switch stage {
            case .inProgress: return .inProgress
            case .queued: return .queued
            case .readyForDev: return .readyForDev
            }
        }
        // The active milestone means "ready for dev" now, not "queued": Queued is the wait for a free
        // agent slot, which a milestone cannot know about.
        if let active = input.activeMilestone, issue.milestone?.title == active { return .readyForDev }
        return .backlog
    }

    /// The stored stage for a card, or nil for the ids git owns: a `branch:`, `pr:` or `merged:` card's
    /// column is a fact about commits and pull requests, and a stale entry under one of those ids must
    /// not move it (ADR 0035).
    private func stage(for id: String) -> BoardStage? {
        guard !id.hasPrefix("branch:"), !id.hasPrefix("pr:"), !id.hasPrefix("merged:") else { return nil }
        return input.stages[id]
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
        // A fork's head names a branch of someone else's repository; a branch here with that name is a different one.
        let fromFork = branch == nil && pullRequest?.isCrossRepository == true
        let state = head.flatMap { input.pipeline[$0] }
        let badge: StatusBadge?
        // The ahead count is a field on every card now, so the pill that repeated it stays out of the card and
        // keeps only the dialog's header, where nothing else says how far ahead the branch is.
        var saysAheadOnly = false
        if isDeferred {
            badge = StatusBadge(.neutral, "Deferred")
        } else if let pullRequest {
            badge = BoardBuilder.reviewBadge(pullRequest)
        } else if column == .inProgress, let local {
            badge = BoardBuilder.aheadBadge(local.unmerged)
            saysAheadOnly = true
        } else {
            badge = nil
        }
        return DeskTask(
            id: String(issue.number), issueNumber: issue.number, title: issue.title, column: column,
            cardBadge: saysAheadOnly ? nil : badge,
            cardNote: state?.cardNote ?? (column == .queued ? BoardBuilder.queuedNote : nil),
            headerBadge: badge ?? StatusBadge(.neutral, column == .readyForDev ? "Ready for dev" : column == .queued ? "Queued" : "Backlog"),
            branchLine: branchLine(head, local: local), parallelLine: parallelLine(head, local: local),
            branch: fromFork ? nil : head, noBranchNote: fromFork ? BoardBuilder.forkNote : nil,
            nextAction: nextAction(local: local, pullRequestURL: pullRequest?.url, issueURL: issue.url),
            pipeline: state?.progress,
            activity: activity(head, local: local),
            requirements: .available(BoardBuilder.requirements(body: issue.body, title: issue.title, source: "Issue #\(issue.number)")),
            changes: changes(head, local: local),
            evidence: evidence(pullRequest: pullRequest?.number, state: state),
            dependencies: BoardBuilder.dependencies(issue.body),
            parallel: parallel(head, local: local),
            impact: DeskTask.rating("impact", in: issue.labelNames),
            complexity: DeskTask.rating("complexity", in: issue.labelNames),
            lastCommit: fromFork ? nil : local?.lastCommit, unmergedCount: fromFork ? nil : local?.countedUnmerged,
            pullRequestNumber: pullRequest?.number)
    }

    private func pullRequestTask(_ pullRequest: GitHubPullRequest) -> DeskTask {
        let head = pullRequest.headRefName.isEmpty ? nil : pullRequest.headRefName
        let local = head.flatMap { branchByName[$0] }
        let state = head.flatMap { input.pipeline[$0] }
        let badge = BoardBuilder.reviewBadge(pullRequest)
        return DeskTask(
            // A draft is still being worked on, so it sits with the work, not in Review (ADR 0035).
            id: "pr:\(pullRequest.number)", title: pullRequest.title, column: pullRequest.isDraft ? .inProgress : .review,
            cardMeta: "PR #\(pullRequest.number)", cardBadge: badge, cardNote: state?.cardNote, headerBadge: badge,
            branchLine: branchLine(head, local: local), parallelLine: parallelLine(head, local: local),
            branch: pullRequest.isCrossRepository ? nil : head, noBranchNote: pullRequest.isCrossRepository ? BoardBuilder.forkNote : nil,
            nextAction: nextAction(local: local, pullRequestURL: pullRequest.url, issueURL: nil),
            pipeline: state?.progress,
            activity: activity(head, local: local),
            requirements: .available(BoardBuilder.requirements(body: pullRequest.body, title: pullRequest.title,
                                                               source: "Pull request #\(pullRequest.number)")),
            changes: changes(head, local: local),
            evidence: evidence(pullRequest: pullRequest.number, state: state),
            dependencies: BoardBuilder.dependencies(pullRequest.body),
            parallel: parallel(head, local: local),
            lastCommit: pullRequest.isCrossRepository ? nil : local?.lastCommit,
            unmergedCount: pullRequest.isCrossRepository ? nil : local?.countedUnmerged,
            pullRequestNumber: pullRequest.number)
    }

    private func branchTask(_ branch: BranchFacts) -> DeskTask {
        let state = input.pipeline[branch.name]
        let badge = BoardBuilder.aheadBadge(branch.unmerged)
        return DeskTask(
            id: "branch:\(branch.name)", title: branch.name, column: .inProgress,
            cardBadge: nil, cardNote: state?.cardNote, headerBadge: badge,
            branchLine: branchLine(branch.name, local: branch), parallelLine: parallelLine(branch.name, local: branch),
            branch: branch.name,
            nextAction: .reviewChanges,
            pipeline: state?.progress,
            activity: activity(branch.name, local: branch),
            requirements: .unavailable(BoardBuilder.unlinkedRequirements),
            changes: changes(branch.name, local: branch),
            evidence: evidence(pullRequest: nil, state: state),
            parallel: parallel(branch.name, local: branch),
            lastCommit: branch.lastCommit, unmergedCount: branch.countedUnmerged)
    }

    /// A card for work that exists only as a file. No issue, no branch yet: its Overview is the file itself.
    /// The stored stage is the only thing that can move it forward — there is no milestone and no pull
    /// request to consult — so it reads its column from `.devdesk/board.json` and stays local either way.
    private func localTask(_ item: BacklogItem) -> DeskTask {
        let path = "\(LocalBacklog.folder)/\(item.id).md"
        let id = DeskTask.localPrefix + item.id
        let column: BoardColumn
        switch stage(for: id) {
        case .inProgress: column = .inProgress
        case .queued: column = .queued
        case .readyForDev: column = .readyForDev
        case nil: column = .backlog
        }
        return DeskTask(
            id: id, title: item.title, column: column,
            cardMeta: item.area, cardBadge: StatusBadge(.info, "Local"),
            cardNote: column == .queued ? BoardBuilder.queuedNote : nil,
            headerBadge: StatusBadge(.info, "Local backlog"),
            branchLine: "No branch yet", parallelLine: "",
            // The source is rendered as markdown, and a file name is the repository's text — a file called
            // "[open](file:///…).md" would otherwise arrive as a link.
            requirements: .available(BoardBuilder.requirements(body: item.body, title: item.title, source: Markdown.escape(path))),
            changes: .unavailable("Nothing has been started for this yet."),
            evidence: .unavailable("Nothing has been started for this yet."),
            parallel: .none("No branch yet"),
            impact: item.impact, complexity: item.complexity)
    }

    private func mergedTask(_ pullRequest: GitHubMergedPullRequest) -> DeskTask {
        let day = pullRequest.mergedAt.map { String($0.prefix(10)) }
        let reason = (day.map { "Merged on \($0)." } ?? "Merged.")
            + " Dev Desk reads only open work; open the pull request for its description, commits, diff and checks."
        return DeskTask(
            id: "merged:\(pullRequest.number)", issueNumber: pullRequest.number, title: pullRequest.title, column: .done,
            cardMeta: "merged", isDimmed: true, headerBadge: StatusBadge(.ended, "Merged"),
            branchLine: [pullRequest.headRefName, day.map { "merged \($0)" } ?? "merged"].filter { !$0.isEmpty }.joined(separator: " · "),
            branch: pullRequest.isCrossRepository || pullRequest.headRefName.isEmpty ? nil : pullRequest.headRefName,
            noBranchNote: pullRequest.isCrossRepository ? BoardBuilder.forkNote : nil,
            nextAction: URL(string: pullRequest.url).map { .openURL($0, title: "Open pull request") },
            activity: .unavailable(reason),
            requirements: .unavailable(reason),
            changes: .unavailable(reason),
            evidence: .unavailable(reason),
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
