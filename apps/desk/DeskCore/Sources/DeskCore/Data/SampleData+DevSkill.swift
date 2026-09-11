extension SampleData {
    public static func devSkill() -> ProjectSnapshot {
        ProjectSnapshot(
            project: ProjectInfo(name: "dev-skill", displayPath: "~/code/dev-skill", branch: "main"),
            isDemo: true,
            board: .available(devSkillTasks()),
            boardNote: "Separate window, separate selection and layout. Work in StudyHub is unaffected by what happens here.",
            findings: .available(FindingsReport(runs: [], findings: [])),
            roadmap: .available(Roadmap(
                note: "Work type, priority, and commitment are separate properties. Committed items link to Board tasks instead of duplicating them.",
                themes: [], milestones: []
            )),
            decisions: .available([]),
            connections: studyHubConnections(),
            connectionsNote: "Illustrative prototype states. No tools are installed or called.",
            capabilities: studyHubCapabilities(),
            insights: .unavailable("The dev-skill sample window has no scripted conversation."),
            projectFacts: [KeyValue("Base branch", "main", monospaced: true)]
        )
    }

    private static func devSkillTasks() -> [DeskTask] {
        [
            DeskTask(
                id: "12", issueNumber: 12, title: "Survey run summaries", column: .inProgress,
                cardMeta: "feat/run-summary",
                headerBadge: StatusBadge(.neutral, "In progress"), branchLine: "feat/run-summary · base main",
                requirements: .available(Requirements(goal: "Survey run summaries", sources: "Issue #12")),
                changes: .available(ChangeSet(files: [], baseNote: "No diff is included for this task in the demo.")),
                evidence: .available(Evidence(isDemo: true, limitations: "No checks recorded for this task.")),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
            DeskTask(
                id: "9", issueNumber: 9, title: "Decision gate copy pass", column: .review,
                cardMeta: "docs/gates",
                headerBadge: StatusBadge(.info, "In review"), branchLine: "docs/gates · base main",
                requirements: .available(Requirements(goal: "Decision gate copy pass", sources: "Issue #9")),
                changes: .available(ChangeSet(files: [], baseNote: "No diff is included for this task in the demo.")),
                evidence: .available(Evidence(isDemo: true, limitations: "No checks recorded for this task.")),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
            DeskTask(
                id: "4", issueNumber: 4, title: "CLI discovery handshake", column: .done,
                cardMeta: "main", isDimmed: true,
                headerBadge: StatusBadge(.ended, "Done"), branchLine: "main",
                requirements: .available(Requirements(goal: "CLI discovery handshake", sources: "Issue #4")),
                changes: .available(ChangeSet(files: [], baseNote: "No diff is included for this task in the demo.")),
                evidence: .available(Evidence(isDemo: true, limitations: "No checks recorded for this task.")),
                agentsNote: "No agent assigned",
                parallel: .none("No agent assigned")
            ),
        ]
    }
}
