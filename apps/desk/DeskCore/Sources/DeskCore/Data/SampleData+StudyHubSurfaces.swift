extension SampleData {
    public static func studyHub() -> ProjectSnapshot {
        ProjectSnapshot(
            project: ProjectInfo(name: "StudyHub", displayPath: "~/code/studyhub", branch: "main",
                                  remote: "github.com/acme/studyhub", headRevision: "9c2e410"),
            isDemo: true,
            launch: LaunchState(selectedTaskID: "42"),
            activitySummary: StatusBadge(.running, "2 running · 1 waiting", pulses: true),
            board: .available(studyHubTasks()),
            boardNote: "Columns map to prototype labels, not the repository's status field yet.",
            findings: .available(studyHubFindings()),
            roadmap: .available(studyHubRoadmap()),
            connections: studyHubConnections(),
            connectionsNote: "Illustrative prototype states. No tools are installed or called.",
            capabilities: studyHubCapabilities(),
            insights: .demo(studyHubInsightsScript()),
            projectFacts: [
                KeyValue("Base branch", "main", monospaced: true),
                KeyValue("Remote", "github.com/acme/studyhub", monospaced: true),
                KeyValue("Parallel task checkouts", "~/.devdesk/wt", monospaced: true),
            ]
        )
    }

    static func studyHubConnections() -> [Connection] {
        [
            Connection(id: "codex", name: "Codex", state: .connected, label: "connected"),
            Connection(id: "claude", name: "Claude", state: .connected, label: "connected"),
            Connection(id: "gemini", name: "Gemini", state: .notConnected, label: "not connected"),
            Connection(id: "github", name: "GitHub", state: .unavailable, label: "unavailable"),
        ]
    }

    static func studyHubCapabilities() -> CapabilityMatrix {
        CapabilityMatrix(
            providers: ["Codex", "Claude", "Gemini"],
            rows: [
                CapabilityRow(id: "terminal", name: "Interactive terminal", values: [.yes, .yes, .unknown]),
                CapabilityRow(id: "resume", name: "Resume an ended session", values: [.yes, .sometimes, .unknown]),
                CapabilityRow(id: "attach", name: "Attach to an external session", values: [.sometimes, .no, .unknown]),
            ],
            note: "Illustrative prototype states. No provider has been selected or validated for production, and capabilities are read from the connection rather than assumed. Changing the provider never replaces the identity of an existing conversation — a handoff starts a new session."
        )
    }

    static func studyHubFindings() -> FindingsReport {
        FindingsReport(
            runs: [SurveyRun(id: "run-0940", label: "today 09:40", revision: "9c2e410")],
            findings: [
                Finding(
                    id: "F-108", runID: "run-0940", title: "Navigation resets list state on unmount",
                    listDetail: "Known · new evidence · relates to #42",
                    categories: [.knownNewEvidence, .needsDecision],
                    summary: "The course list clears its stored offset in a cleanup effect that also runs on filter changes, so a later return finds no saved position. Observed by reading the code path; not reproduced in a running app.",
                    verificationLabel: "Code-inspected · not reproduced",
                    locations: [
                        "src/features/courses/useScrollRestore.ts:18",
                        "src/features/courses/CourseList.tsx:63",
                        "src/navigation/stackEntry.ts:27",
                    ],
                    limits: "Inspected revision `9c2e410`. No runtime reproduction, no device testing, no measurement of frequency.",
                    reconcile: Reconciliation(
                        candidateIssue: 42,
                        statusNote: "Candidate match found · nothing has been sent to the tracker",
                        guidance: [
                            "Same problem → link the finding and propose adding new evidence to #42.",
                            "Related but independent → keep separate and record the relationship.",
                            "Possible duplicate → compare scope and evidence before choosing a canonical issue.",
                            "Closed issue → inspect possible recurrence; closure alone does not establish a fix.",
                        ],
                        findingCard: CompareCard(title: "Finding F-108", body: "Navigation resets list state on unmount.",
                                                  meta: "useScrollRestore.ts:18 · CourseList.tsx:63\nrev 9c2e410 · code-inspected", metaMonospaced: true),
                        issueCard: CompareCard(title: "Issue #42", body: "Returning from a lesson resets scroll position.",
                                                meta: "Opened from a user report · 1 linked finding · in progress", metaMonospaced: false),
                        relationships: [
                            RelationshipOption(id: "same", title: "Same problem", detail: "link the finding and propose adding its evidence to #42."),
                            RelationshipOption(id: "related", title: "Related but independent", detail: "keep separate and record the relationship."),
                            RelationshipOption(id: "duplicate", title: "Possible duplicate", detail: "compare scope before choosing a canonical issue."),
                            RelationshipOption(id: "unconfirmed", title: "Unconfirmed observation", detail: "retain the finding without presenting it as a confirmed issue."),
                        ],
                        proposedUpdate: [
                            "comment on #42:",
                            "+ Survey F-108 (rev 9c2e410, code-inspected, not reproduced)",
                            "+ Locations: useScrollRestore.ts:18, CourseList.tsx:63",
                            "+ No status change proposed",
                        ],
                        deliveryNote: "GitHub is unavailable — the update will be queued locally until the connection returns. Nothing is created silently."
                    ),
                    historyNote: "Three surveys have produced evidence for this finding since 4 Sep. History is preserved on the finding rather than filed as repeated tickets."
                ),
                Finding(
                    id: "F-111", runID: "run-0940", title: "Exam attempt store writes twice",
                    listDetail: "New · unconfirmed observation",
                    categories: [.new],
                    summary: "Attempt writes may pass through `attemptStore.ts` twice for one answer. Seen while reading the code path; the checker could not confirm it from the code alone.",
                    verificationLabel: "Unconfirmed observation",
                    locations: ["src/features/exams/attemptStore.ts"],
                    limits: "Inspected revision `9c2e410`. Not confirmed from the code and not reproduced."
                ),
                Finding(
                    id: "F-093", runID: "run-0940", title: "Search index rebuilt per keystroke",
                    listDetail: "Previously declined · see reason",
                    categories: [.closedOrDeclined],
                    summary: "The lesson search index is rebuilt on every keystroke.",
                    verificationLabel: "Code-inspected · not reproduced",
                    locations: [],
                    limits: "Inspected revision `9c2e410`. Declined on 28 Aug; see Decisions › History, “Decline search index rewrite”.",
                    historyNote: "Previously declined. Reconsider only with a documented change in circumstances."
                ),
            ],
            searchNote: "Issue search is unavailable (GitHub disconnected). This is different from a search that returned nothing."
        )
    }

    static func studyHubRoadmap() -> Roadmap {
        Roadmap(
            note: "Work type, priority, and commitment are separate properties. Committed items link to Board tasks instead of duplicating them.",
            themes: [
                RoadmapTheme(id: "continuity", title: "Theme · Learning continuity", items: [
                    RoadmapItem(id: "resume", title: "Resume where you left off", workType: "Epic", priority: "High",
                                commitment: .committed, linkText: "Board: [#42](desk://task/42), [#57](desk://task/57) · Milestone 1.4"),
                    RoadmapItem(id: "offline", title: "Offline lesson cache", workType: "Feature", priority: "Medium", commitment: .considered),
                ]),
                RoadmapTheme(id: "performance", title: "Theme · Performance", items: [
                    RoadmapItem(id: "search", title: "Search responsiveness", workType: "Improvement", priority: "Medium",
                                commitment: .committed, linkText: "Board: [#63](desk://task/63) (investigation)"),
                ]),
                RoadmapTheme(id: "critical", title: "Critical concerns", isCritical: true, items: [
                    RoadmapItem(id: "exam", title: "Exam progress can be lost", workType: "Defect", priority: "Urgent",
                                commitment: .committed, isCritical: true,
                                linkText: "Entered the Board directly as [#57](desk://task/57); roadmap context retained."),
                ]),
            ],
            milestones: [
                Milestone(id: "m14", title: "1.4 · Continuity", progress: 0.55, note: "2 of 4 tasks · no date committed"),
                Milestone(id: "m15", title: "1.5 · Performance", progress: 0.15, note: "1 of 6 tasks · investigation stage"),
            ]
        )
    }

    static func studyHubInsightsScript() -> InsightsScript {
        InsightsScript(
            provider: "Codex",
            providers: ["Codex", "Claude"],
            chips: [
                ContextChip(id: "project", label: "Project StudyHub"),
                ContextChip(id: "task", label: "Task #42", isTask: true),
                ContextChip(id: "finding", label: "Finding F-108"),
            ],
            initial: [
                InsightsMessage(author: "You", text: "Why does returning from a lesson lose the scroll position?", isUser: true),
                InsightsMessage(author: "Insights · Codex",
                                 text: "The course list stores its offset in a cleanup effect that also runs when the filter changes, so the value is cleared before the list is re-entered. This is read from code; the symptom has not been reproduced in a running app.",
                                 citation: "useScrollRestore.ts:18 · CourseList.tsx:63 · finding F-108", isUser: false),
            ],
            freeformReply: InsightsReply(
                text: "Exploration is read-only, so nothing was changed. Based on the current revision, the relevant code path is the course list restore effect and the navigation stack entry that records the source of entry.",
                citation: "useScrollRestore.ts:18 · stackEntry.ts:27 · PROJECT_MAP.md § Navigation"
            ),
            quickActions: [
                InsightsQuickAction(id: "survey", title: "Run survey", reply: InsightsReply(
                    text: "Survey is a separate workflow. Opening it in Findings with the current revision preselected — this chat will not run it silently.",
                    citation: "Findings › Run survey")),
                InsightsQuickAction(id: "roadmap", title: "Explore roadmap", reply: InsightsReply(
                    text: "Continuity is the theme with the most committed work. Two Board tasks are attached to milestone 1.4, and one considered item has no commitment yet.",
                    citation: "Roadmap › Learning continuity")),
                InsightsQuickAction(id: "save", title: "Save project knowledge", reply: InsightsReply(
                    text: "Proposed for PROJECT_MAP.md § Navigation: “List scroll offsets are stored per filter in session storage.” This is supported by code and needs your approval before it is saved.",
                    citation: "PROJECT_MAP.md · pending approval")),
                InsightsQuickAction(id: "continue", title: "Continue task conversation", reply: InsightsReply(
                    text: "This targets the #42 session directly. The running agent receives the message; project exploration stops here and the work continues in the task.",
                    citation: "Task #42 · Codex session 3f9a"), dockedOnly: true),
            ],
            footnote: "Exploration is read-only. Asking here does not steer the agent working on #42."
        )
    }
}
