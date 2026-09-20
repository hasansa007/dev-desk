# Architecture Decision Records

One file per decision, `NNNN-kebab-title.md`. The number is allocated by reading this directory,
never guessed. A landed ADR's `## Decision` is never edited — it is superseded by a new one and its
`Status:` updated to point there. An ADR with an empty `## Rejected` is a note, not an ADR.

Owned by `dev:docs`, which requires one for any diff carrying a decision with a rejected
alternative. See [0001](0001-adrs-live-in-docs-adr.md) for the convention itself.

| # | Decision | Status |
|---|---|---|
| [0001](0001-adrs-live-in-docs-adr.md) | ADRs live in `docs/adr/`, numbered, superseded rather than edited | Accepted |
| [0002](0002-diagrams-land-in-the-repo.md) | Evidenced diagrams land in `docs/arch/`, with their IR beside them | Accepted, amended by 0033 |
| [0003](0003-the-staleness-probe-bumps-the-revision.md) | The diagram staleness probe bumps the revision to HEAD | Accepted |
| [0004](0004-compare-cited-paths-not-the-whole-tree.md) | Compare cited paths, not the whole tree, before advancing a pin | Accepted |
| [0005](0005-re-assert-head-before-validating.md) | Re-assert HEAD before validating, not only at the start | Accepted |
| [0006](0006-ask-for-their-approach-before-showing-yours.md) | The walkthrough gate always asks; the rule governs depth | Accepted |
| [0007](0007-raise-the-pipeline-line-ceiling-to-988.md) | Raise the pipeline line ceiling to 988, and install the check | Accepted |
| [0008](0008-replace-the-board-add-the-opportunity-door.md) | Replace the board; add the opportunity door rather than merge it | Accepted |
| [0009](0009-track-docs-so-an-adr-can-be-part-of-its-own-diff.md) | Track `docs/` so an ADR can be part of the diff that introduces it | Accepted |
| [0010](0010-paths-point-at-the-install-root.md) | Paths point at the install root, not the clone | Accepted — amended by 0054 |
| [0011](0011-the-project-board-mirrors-it-never-decides.md) | The Project board mirrors; it never decides | Accepted, partially reversed by 0035 |
| [0012](0012-the-mac-app-lives-in-apps-desk.md) | The Mac app lives in `apps/desk/`, in this repo | Accepted |
| [0013](0013-the-app-reads-git-and-github-directly.md) | The app reads git and GitHub directly, until `dev snapshot` exists | Accepted |
| [0014](0014-dev-desk-replaces-dev-ui.md) | Dev Desk replaces `/dev:ui`; card moves go through `/dev:board` | Accepted |
| [0015](0015-files-live-with-the-flow-that-reads-them.md) | Files live with the flow that reads them; the root holds only entry points and folders with a reader | Accepted |
| [0016](0016-dev-desk-embeds-a-terminal-with-swiftterm.md) | Dev Desk embeds a terminal with SwiftTerm, its first dependency; DeskCore stays dependency-free | Accepted, reversed by 0036 |
| [0017](0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md) | A task's shell opens in that task's own worktree, and only when asked | Accepted, amended by 0036 |
| [0018](0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md) | Dev Desk starts the task's agent, by hand or in Auto for queued tasks | Accepted, amended by 0030, 0036 |
| [0019](0019-deep-features-cant-skip-the-architecture-gate.md) | Deep features can't skip the architecture gate; dev:audit checks it | Accepted |
| [0020](0020-impact-and-complexity-are-labels-the-doors-propose.md) | Impact and complexity are labels the doors propose and the developer corrects | Accepted, amended by 0038 |
| [0021](0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md) | A card opens one dialog, and the panels are the window's edges | Accepted, amended by 0028, 0032, 0038, 0039 |
| [0022](0022-dev-desk-deletes-a-local-branch-and-nothing-else.md) | Dev Desk deletes a local branch, and nothing else | Accepted, amended by 0023, 0029 |
| [0023](0023-the-gate-ran-late-and-took-the-fold-with-it.md) | The gate ran late, and took the fold with it | Accepted, amended by 0024 |
| [0024](0024-a-board-card-is-one-block-and-its-chrome-is-one-modifier.md) | A board card is one block, and its chrome is one modifier | Accepted |
| [0025](0025-a-background-run-belongs-to-the-app-not-the-window.md) | A background run belongs to the app, not the window | Accepted, amended by 0031 |
| [0026](0026-a-task-has-one-session-and-terminals-is-where-it-lives.md) | A task has one session, and Terminals is where it lives | Accepted, amended by 0036 |
| [0027](0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md) | Work without a tracker is recorded locally, and promoted on request | Accepted |
| [0028](0028-the-window-fits-an-ipad-and-a-dialog-clamps-to-it.md) | The window fits an iPad, and a dialog clamps to it | Accepted |
| [0029](0029-a-survey-reset-trashes-older-reports.md) | A survey reset trashes older reports | Accepted |
| [0030](0030-insights-runs-its-agent-headlessly.md) | Insights runs its agent headlessly (`claude -p` / `codex exec`) | Accepted |
| [0031](0031-a-killed-run-leaves-a-record-and-the-next-launch-offers-to-continue-it.md) | A killed run leaves a record, and the next launch offers to continue it | Accepted |
| [0032](0032-a-tapped-file-opens-beside-the-work-or-floats-over-it.md) | A tapped file opens beside the work, or floats over it | Accepted |
| [0033](0033-every-diagram-type-lands-in-docs-arch.md) | Every diagram type lands in `docs/arch/`, labelled rather than hidden | Accepted |
| [0034](0034-a-failed-headless-run-keeps-its-evidence.md) | A failed headless run keeps its evidence, and one rule places every prompt | Accepted |
| [0035](0035-the-board-stores-what-git-cannot-see.md) | The board stores what git cannot see (`.devdesk/board.json`) | Accepted, amended by 0037 |
| [0036](0036-agents-run-over-a-protocol-and-the-terminal-leaves-the-app.md) | Agents run over a protocol (ACP), and the terminal leaves the app | Accepted |
| [0037](0037-a-local-card-carries-its-own-done.md) | A `docs/backlog/` card's Done comes from its own file, not `board.json` | Accepted |
| [0038](0038-the-survey-is-a-triage-list-and-board-controls-live-on-their-columns.md) | The survey is a triage list, and the board's controls live on their columns | Accepted |
| [0039](0039-a-confirmation-is-as-big-as-its-question.md) | A confirmation is as big as its question, and a survey reset asks about the cards it filed | Accepted |
| [0040](0040-a-survey-files-tickets-in-groups-and-names-the-code-they-share.md) | A survey files tickets in groups, and names the code they share | Accepted |
| [0041](0041-a-survey-reset-clears-the-findings-and-keeps-work-in-progress.md) | A survey reset clears the findings and what they filed, and keeps work in progress | Accepted |
| [0042](0042-survey-is-renamed-findings-in-the-app-the-door-and-the-folder.md) | Survey is renamed Findings, in the app, the door and the folder | Accepted |
| [0043](0043-a-findings-run-is-told-its-stops-before-it-starts.md) | A findings run is told its stops before it starts, and refuses past its agent limit | Accepted |
| [0044](0044-a-card-moves-on-its-runs-checkpoints-not-on-a-terminal.md) | A card moves on its run's checkpoints, not on a terminal opening | Accepted |
| [0045](0045-add-task-files-where-the-tracker-is-checks-for-duplicates-and-can-start.md) | Add Task files where the tracker is, checks for duplicates first, and can start the work | Accepted |
| [0046](0046-one-task-model-three-views-findings-keeps-its-name.md) | One task model in three views — Board, Plan, Findings, one filter bar; Findings keeps its name | Accepted |
| [0047](0047-diagrams-are-architecture-data-flow-and-one-sequence-per-flow.md) | Diagrams are Architecture, Data flow and one Sequence per flow — every flow source counts the same | Accepted |
| [0048](0048-the-board-drops-the-p0-strip.md) | The Board drops the P0 strip | Accepted |
| [0049](0049-a-ticket-fans-out-into-slices-under-an-orchestrator.md) | A ticket fans out into slices under an orchestrator, and its decisions are front-loaded | Accepted — design |
| [0050](0050-one-window-holds-every-project-and-the-strip-switches-them.md) | One window holds every project, and the strip switches them | Accepted |
| [0051](0051-in-progress-gets-the-width-and-a-card-has-a-second-shape.md) | In progress gets the width, and a card has a second shape | Accepted |
| [0052](0052-the-bottom-edge-is-a-dock-that-holds-several-terminals.md) | The bottom edge is a dock that holds several terminals | Accepted |
| [0053](0053-kanban-is-renamed-board-in-the-door-and-the-folder.md) | Kanban is renamed Board, in the door and the folder | Accepted |
| [0054](0054-the-install-root-is-one-hidden-symlink-not-a-skills-directory.md) | The install root is one hidden symlink, not a skills directory | Accepted |
