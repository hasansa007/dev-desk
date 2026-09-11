extension SampleData {
    private static let running = StatusBadge(.running, "Running", pulses: true)

    private static func emptyRequirements(goal: String, sources: String) -> Surface<Requirements> {
        .available(Requirements(goal: goal, sources: sources))
    }

    private static func emptyChanges(note: String) -> Surface<ChangeSet> {
        .available(ChangeSet(files: [], baseNote: note))
    }

    private static func emptyEvidence(limitations: String? = nil) -> Surface<Evidence> {
        .available(Evidence(isDemo: true, limitations: limitations))
    }

    static func studyHubTasks() -> [DeskTask] {
        [
            DeskTask(
                id: "71", issueNumber: 71, title: "Offline lesson cache", column: .backlog,
                headerBadge: StatusBadge(.neutral, "Backlog"), branchLine: "No branch yet",
                requirements: emptyRequirements(goal: "Offline lesson cache", sources: "Issue #71 · roadmap item “Offline lesson cache” (considered)"),
                changes: emptyChanges(note: "No branch yet."),
                evidence: emptyEvidence(),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
            DeskTask(
                id: "68", issueNumber: 68, title: "Flashcard deck import", column: .backlog,
                headerBadge: StatusBadge(.neutral, "Backlog"), branchLine: "No branch yet",
                requirements: emptyRequirements(goal: "Flashcard deck import", sources: "Issue #68"),
                changes: emptyChanges(note: "No branch yet."),
                evidence: emptyEvidence(),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
            DeskTask(
                id: "65", issueNumber: 65, title: "Reduce initial bundle size", column: .queued,
                cardInlineText: "No agent assigned",
                headerBadge: StatusBadge(.neutral, "Queued"), branchLine: "No branch yet",
                requirements: emptyRequirements(goal: "Reduce initial bundle size", sources: "Issue #65"),
                changes: emptyChanges(note: "No branch yet."),
                evidence: emptyEvidence(),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
            DeskTask(
                id: "42", issueNumber: 42, title: "Preserve course-list position", column: .inProgress,
                cardBadge: running, cardNote: "Codex primary · reviewer · verifier",
                headerBadge: running,
                branchLine: "fix/42-course-scroll · worktree ~/.devdesk/wt/studyhub-42 · base main@9c2e410",
                parallelLine: "fix/42-course-scroll · ~/.devdesk/wt/studyhub-42",
                nextAction: .reviewChanges,
                pipeline: PipelineProgress(stages: [
                    PipelineStage("Investigated", .done),
                    PipelineStage("Planned", .done),
                    PipelineStage("Implementing", .current),
                    PipelineStage("Verified", .pending),
                ]),
                activity: .available([
                    ActivityEvent(id: "42-a1", time: "11:12", text: "**Codex** patched `useScrollRestore.ts`",
                                  detail: ToolDetail(title: "Tool detail · edit_file", lines: [
                                      "path: src/features/courses/useScrollRestore.ts",
                                      "range: 12–38 · +24 −6",
                                      "result: applied",
                                  ])),
                    ActivityEvent(id: "42-a2", time: "11:07", text: "**Reviewer** (activity only) flagged a missing cleanup on unmount.", offersFollowUp: true),
                    ActivityEvent(id: "42-a3", time: "10:49", text: "**Verifier** finished: 18 unit checks passed, no runtime reproduction attempted."),
                    ActivityEvent(id: "42-a4", time: "10:31", text: "Plan approved by you · 3 acceptance criteria accepted."),
                    ActivityEvent(id: "42-a5", time: "10:12", text: "Task created from issue #42 and survey finding F-108."),
                ]),
                canCompareOutputs: true,
                requirements: .available(Requirements(
                    goal: "Returning from a lesson to the course list restores the previous scroll position and selected course, including after a back-navigation from a deep link.",
                    criteria: [
                        AcceptanceCriterion("Scroll offset is restored within one frame of the list mounting.", isMet: true),
                        AcceptanceCriterion("Position survives a filter change made before leaving the list.", isMet: true),
                        AcceptanceCriterion("No restoration is attempted when the list is entered fresh from search.", isMet: false),
                    ],
                    outOfScope: "Virtualised list rewrite (tracked as #71). Cross-device position sync.",
                    sources: "User report on issue #42 · survey finding F-108 (code-inspected) · PROJECT_MAP.md § Navigation."
                )),
                changes: .available(ChangeSet(
                    files: [
                        ChangedFile(id: "src/features/courses/useScrollRestore.ts", displayPath: "courses/useScrollRestore.ts", additions: 24, deletions: 6),
                        ChangedFile(id: "src/features/courses/CourseList.tsx", displayPath: "courses/CourseList.tsx", additions: 9, deletions: 2),
                        ChangedFile(id: "src/features/courses/__tests__/scroll.test.ts", displayPath: "courses/__tests__/scroll.test.ts", additions: 41, deletions: 0),
                    ],
                    baseNote: "Diff is against `main` at `9c2e410`. Demo content.",
                    diffs: [
                        "src/features/courses/useScrollRestore.ts": FileDiff(
                            path: "src/features/courses/useScrollRestore.ts",
                            hunks: [DiffHunk(header: "@@ -12,6 +12,24 @@", lines: [
                                DiffLine(.context, "const key = `course-list:${filterId}`;"),
                                DiffLine(.deletion, "useEffect(() => { window.scrollTo(0, 0); }, []);"),
                                DiffLine(.addition, "useLayoutEffect(() => {"),
                                DiffLine(.addition, "  const saved = sessionStore.get(key);"),
                                DiffLine(.addition, "  if (saved != null && entry.source !== 'search') {"),
                                DiffLine(.addition, "    listRef.current?.scrollTo({ top: saved });"),
                                DiffLine(.addition, "  }"),
                                DiffLine(.addition, "  return () => sessionStore.set(key, listRef.current?.scrollTop ?? 0);"),
                                DiffLine(.addition, "}, [key, entry.source]);"),
                                DiffLine(.context, "return listRef;"),
                            ])]
                        ),
                    ]
                )),
                evidence: .available(Evidence(
                    isDemo: true,
                    checks: [
                        CheckResult(id: "unit", name: "Unit tests · courses", outcome: .passed, outcomeLabel: "18 passed", revisionLabel: "rev 7b31e0c"),
                        CheckResult(id: "types", name: "Type check", outcome: .passed, outcomeLabel: "clean", revisionLabel: "rev 7b31e0c"),
                        CheckResult(id: "lint", name: "Lint", outcome: .warning, outcomeLabel: "2 warnings", revisionLabel: "rev 7b31e0c"),
                        CheckResult(id: "e2e", name: "End-to-end · navigation", outcome: .failed, outcomeLabel: "failed to start", revisionLabel: "runner unavailable"),
                    ],
                    failure: FailedRun(title: "Failed run · navigation e2e", message: "The browser runner could not launch in this environment. No conclusion can be drawn about the scroll behaviour from this run."),
                    limitations: "Behaviour was inspected in code and covered by unit tests. The reported symptom has not been reproduced in a running app, so this task is not verified end to end.",
                    linked: [LinkedEvidence(title: "Survey finding F-108 · Navigation resets list state on unmount", badge: "Code-inspected", findingID: "F-108")]
                )),
                agents: [
                    AgentSession(id: "codex", name: "Codex", role: "Primary", capability: .interactive, stateLabel: "Interactive session · running", tone: .running, pulses: true, actions: [.openTerminal, .stop]),
                    AgentSession(id: "reviewer", name: "Reviewer", role: "Helper", capability: .activityOnly, stateLabel: "Activity only · no terminal", tone: .info, actions: [.viewActivity, .requestFollowUp]),
                    AgentSession(id: "verifier", name: "Verifier", role: "Ended", capability: .completedResult, stateLabel: "Completed helper result", tone: .ended, actions: [.readResult]),
                ],
                dependencies: [Dependency(text: "Blocked by [#59](desk://task/59) — shared date helpers are being rewritten in review.", taskID: "59")],
                dock: DockContent(
                    tabs: [
                        DockTab(id: "codex", title: "Codex · #42", transcript: TerminalTranscript(
                            header: "codex session 3f9a · attached · demo output",
                            lines: [
                                TerminalLine(.plain, "› patch src/features/courses/useScrollRestore.ts"),
                                TerminalLine(.success, "✓ applied 24 additions, 6 deletions"),
                                TerminalLine(.plain, "› npm test -- courses"),
                                TerminalLine(.success, "✓ 18 passed"),
                                TerminalLine(.plain, "› npm run e2e -- navigation"),
                                TerminalLine(.failure, "✗ runner unavailable in this environment"),
                            ],
                            showsPrompt: true
                        )),
                        DockTab(id: "shell", title: "Shell · studyhub-42", transcript: TerminalTranscript(
                            header: "zsh · ~/.devdesk/wt/studyhub-42 · demo output",
                            lines: [TerminalLine(.dim, "fix/42-course-scroll · 3 files changed")]
                        )),
                        DockTab(id: "reviewer", title: "Reviewer · activity", transcript: TerminalTranscript(
                            header: "reviewer · activity only · read-only",
                            lines: [
                                TerminalLine(.plain, "· inspected CourseList.tsx (lines 40–96)"),
                                TerminalLine(.plain, "· note: cleanup missing on unmount when filter changes"),
                                TerminalLine(.plain, "· no input accepted — ask the coordinating agent for follow-up"),
                            ],
                            showsPrompt: false, isReadOnly: true
                        )),
                    ],
                    caption: "Agents & Terminals · views of one session, not new agents",
                    splitTabID: "reviewer"
                ),
                parallel: .transcript(TerminalTranscript(
                    header: "codex · session 3f9a · running",
                    lines: [
                        TerminalLine(.plain, "› read src/features/courses/CourseList.tsx"),
                        TerminalLine(.plain, "› patch src/features/courses/useScrollRestore.ts"),
                        TerminalLine(.plain, "› run npm test -- courses"),
                        TerminalLine(.success, "✓ 18 passed, 0 failed (demo output)"),
                    ]
                )),
                comparison: OutputComparison(
                    intro: "Two outputs for the same acceptance criterion. Comparing does not adopt either result; adopting one records the choice on the task.",
                    left: ComparedOutput(title: "Codex · primary", stateLabel: "running", tone: .running,
                                          summaryLines: ["useLayoutEffect + sessionStore", "restores before paint", "skips restore when entry.source === 'search'"],
                                          result: "18 unit checks pass. No runtime reproduction."),
                    right: ComparedOutput(title: "Claude · alternative attempt", stateLabel: "ended", tone: .ended,
                                           summaryLines: ["scroll anchor on list item id", "restores after data resolves", "no special case for search entry"],
                                           result: "16 unit checks pass, 2 skipped. Flickers on slow data."),
                    footnote: "Both ran against revision 7b31e0c. Neither has been verified against the reported symptom.",
                    confirmTitle: "Adopt Codex result"
                ),
                followUp: FollowUpDraft(
                    explanation: "The reviewer is an activity-only helper. It has no terminal and accepts no direct input, so the follow-up is routed through the coordinating agent working on #42.",
                    reviewerNote: "Cleanup is missing on unmount when the filter changes, so the stored offset is dropped before the list is re-entered.",
                    request: "Ask the reviewer to check whether the same cleanup issue affects the lesson list, and attach line references.",
                    recipient: "Codex · coordinating agent for #42"
                )
            ),
            DeskTask(
                id: "57", issueNumber: 57, title: "Improve exam recovery", column: .inProgress,
                cardBadge: StatusBadge(.waiting, "Needs a decision", symbol: "questionmark.diamond"),
                cardNote: "Claude session waiting for input",
                headerBadge: StatusBadge(.waiting, "Waiting for input"),
                branchLine: "feat/57-exam-recovery · worktree ~/.devdesk/wt/studyhub-57 · base main@9c2e410",
                parallelLine: "feat/57-exam-recovery · ~/.devdesk/wt/studyhub-57",
                nextAction: .answerDecision(decisionID: "d-57"),
                notice: .waitingForDecision(
                    title: "Waiting for a decision before implementation continues",
                    message: "The Claude session paused and asked where partial exam state should be persisted. This question arose during implementation, outside a formal pipeline gate.",
                    decisionID: "d-57"
                ),
                activity: .available([
                    ActivityEvent(id: "57-a1", time: "11:04", text: "Session paused and posted a question to Decisions."),
                    ActivityEvent(id: "57-a2", time: "10:58", text: "Read `src/features/exams/attemptStore.ts` and two migrations."),
                    ActivityEvent(id: "57-a3", time: "10:51", text: "Requirements accepted from issue #57."),
                ]),
                requirements: emptyRequirements(goal: "Exam progress is not lost when an attempt is interrupted.", sources: "Issue #57 · roadmap concern “Exam progress can be lost”"),
                changes: emptyChanges(note: "No changes yet. No code has been written against any option."),
                evidence: emptyEvidence(limitations: "No checks have run for this task."),
                agents: [
                    AgentSession(id: "claude", name: "Claude", role: "Primary", capability: .interactive, stateLabel: "Interactive session · waiting for input", tone: .waiting, actions: [.openTerminal, .stop]),
                ],
                dependencies: [Dependency(text: "Touches the same storage layer as [#59](desk://task/59).", taskID: "59")],
                dock: DockContent(
                    tabs: [
                        DockTab(id: "claude", title: "Claude · #57", transcript: TerminalTranscript(
                            header: "claude session 8c21 · waiting for input · demo output",
                            lines: [
                                TerminalLine(.plain, "› read src/features/exams/attemptStore.ts"),
                                TerminalLine(.plain, "› read 2 migrations"),
                                TerminalLine(.dim, "? Where should partial exam state be persisted so an interrupted attempt can resume?"),
                                TerminalLine(.dim, "Waiting for an answer in Decisions."),
                            ],
                            showsPrompt: false
                        )),
                    ],
                    caption: "Agents & Terminals · views of one session, not new agents"
                ),
                parallel: .decision(
                    title: "Blocked on an architecture decision",
                    question: "Where should partial exam state be persisted so an interrupted attempt can resume?",
                    decisionID: "d-57",
                    note: "The Claude session stays open while waiting. Dependencies stay visible: #57 touches the same storage layer as #59."
                )
            ),
            DeskTask(
                id: "63", issueNumber: 63, title: "Investigate slow lesson search", column: .inProgress,
                cardBadge: StatusBadge(.neutral, "Connected · tracking only"),
                cardNote: "External checkout, not managed here",
                headerBadge: StatusBadge(.neutral, "Connected · tracking only"),
                branchLine: "spike/search-profiling · external checkout ~/scratch/studyhub-search",
                parallelLine: "spike/search-profiling · ~/scratch/studyhub-search",
                nextAction: .startHandoff,
                notice: .externalConnection(ExternalConnection(
                    title: "Connected external work · repository tracking only",
                    message: "Dev Desk discovered this checkout at `~/scratch/studyhub-search` with branch `spike/search-profiling` and 7 uncommitted changes. The original session was not started through a supported connection, so it cannot be attached or resumed.",
                    levels: [
                        ConnectionLevel(name: "Repository tracking", isAvailable: true, statusLabel: "Available", detail: "Branch, diff, and commits are readable."),
                        ConnectionLevel(name: "Attach to session", isAvailable: false, statusLabel: "Unavailable", detail: "No live session was found for this checkout."),
                        ConnectionLevel(name: "Continue session", isAvailable: false, statusLabel: "Unavailable", detail: "The provider did not record a resumable session."),
                    ],
                    facts: [
                        KeyValue("Branch", "spike/search-profiling", monospaced: true),
                        KeyValue("Revision inspected", "a41c9d2", monospaced: true),
                        KeyValue("Uncommitted", "7 files · not pushed"),
                    ],
                    handoffNote: "A handoff always appears as a new session. The existing checkout and its uncommitted changes are preserved.",
                    checkoutPath: "~/scratch/studyhub-search"
                )),
                requirements: emptyRequirements(goal: "Find out why lesson search is slow.", sources: "Issue #63 · roadmap item “Search responsiveness” (investigation)"),
                changes: emptyChanges(note: "7 uncommitted files in the external checkout · not pushed. Dev Desk reads this checkout; it does not manage it."),
                evidence: emptyEvidence(limitations: "No checks recorded. An earlier finding in this area (F-093) was declined on 28 Aug."),
                agents: [],
                agentsNote: "No managed session. This checkout is connected for repository tracking only.",
                dock: nil,
                parallel: .none("External checkout, not managed here"),
                handoff: HandoffPlan(
                    warning: "This creates a **new session**. The earlier work is not resumed and its conversation is not adopted. The existing checkout, branch, and uncommitted changes stay as they are.",
                    rows: [
                        KeyValue("Task", "#63 Investigate slow lesson search"),
                        KeyValue("Checkout", "~/scratch/studyhub-search", monospaced: true),
                        KeyValue("Artifacts included", "Requirements, repository diff, 2 prior findings"),
                    ],
                    providers: ["Codex", "Claude"],
                    footnote: "Changing providers is allowed here and is always visible as a new session, never a continuation of the old one."
                )
            ),
            DeskTask(
                id: "59", issueNumber: 59, title: "Fix streak calculation across time zones", column: .review,
                cardBadge: StatusBadge(.ended, "Agent ended"), cardNote: "Blocks #42 · shared date helpers", cardNoteIsWarning: true,
                headerBadge: StatusBadge(.ended, "Agent ended"), branchLine: "fix/59-streak-timezones · base main@9c2e410",
                nextAction: .reviewChanges,
                requirements: emptyRequirements(goal: "Fix streak calculation across time zones", sources: "Issue #59"),
                changes: emptyChanges(note: "No diff is included for this task in the demo."),
                evidence: emptyEvidence(),
                agentsNote: "Agent ended.",
                dependencies: [Dependency(text: "Blocks [#42](desk://task/42) — shared date helpers.", taskID: "42")],
                parallel: .none("Agent ended")
            ),
            DeskTask(
                id: "38", issueNumber: 38, title: "Migrate settings store", column: .done,
                cardMeta: "merged", isDimmed: true,
                headerBadge: StatusBadge(.ended, "Merged"), branchLine: "Merged into main",
                requirements: emptyRequirements(goal: "Migrate settings store", sources: "Issue #38"),
                changes: emptyChanges(note: "Merged into `main`."),
                evidence: emptyEvidence(),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
        ]
    }
}
