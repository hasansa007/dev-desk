# Architecture Decision Records

One file per decision, `NNNN-kebab-title.md`. The number is allocated by reading this directory,
never guessed. A landed ADR's `## Decision` is never edited — it is superseded by a new one and its
`Status:` updated to point there. An ADR with an empty `## Rejected` is a note, not an ADR.

Owned by `dev:docs`, which requires one for any diff carrying a decision with a rejected
alternative. See [0001](0001-adrs-live-in-docs-adr.md) for the convention itself.

| # | Decision | Status |
|---|---|---|
| [0001](0001-adrs-live-in-docs-adr.md) | ADRs live in `docs/adr/`, numbered, superseded rather than edited | Accepted |
| [0002](0002-diagrams-land-in-the-repo.md) | Evidenced diagrams land in `docs/arch/`, with their IR beside them | Accepted |
| [0003](0003-the-staleness-probe-bumps-the-revision.md) | The diagram staleness probe bumps the revision to HEAD | Accepted |
| [0004](0004-compare-cited-paths-not-the-whole-tree.md) | Compare cited paths, not the whole tree, before advancing a pin | Accepted |
| [0005](0005-re-assert-head-before-validating.md) | Re-assert HEAD before validating, not only at the start | Accepted |
| [0006](0006-ask-for-their-approach-before-showing-yours.md) | The walkthrough gate always asks; the rule governs depth | Accepted |
| [0007](0007-raise-the-pipeline-line-ceiling-to-988.md) | Raise the pipeline line ceiling to 988, and install the check | Accepted |
| [0008](0008-replace-the-board-add-the-opportunity-door.md) | Replace the board; add the opportunity door rather than merge it | Accepted |
| [0009](0009-track-docs-so-an-adr-can-be-part-of-its-own-diff.md) | Track `docs/` so an ADR can be part of the diff that introduces it | Accepted |
| [0010](0010-paths-point-at-the-install-root.md) | Paths point at the install root, not the clone | Accepted |
| [0011](0011-the-project-board-mirrors-it-never-decides.md) | The Project board mirrors; it never decides | Accepted |
| [0012](0012-the-mac-app-lives-in-apps-desk.md) | The Mac app lives in `apps/desk/`, in this repo | Accepted |
| [0013](0013-the-app-reads-git-and-github-directly.md) | The app reads git and GitHub directly, until `dev snapshot` exists | Accepted |
| [0014](0014-dev-desk-replaces-dev-ui.md) | Dev Desk replaces `/dev:ui`; card moves go through `/dev:kanban` | Accepted |
| [0015](0015-files-live-with-the-flow-that-reads-them.md) | Files live with the flow that reads them; the root holds only entry points and folders with a reader | Accepted |
| [0016](0016-dev-desk-embeds-a-terminal-with-swiftterm.md) | Dev Desk embeds a terminal with SwiftTerm, its first dependency; DeskCore stays dependency-free | Accepted |
| [0017](0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md) | A task's shell opens in that task's own worktree, and only when asked | Accepted |
| [0018](0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md) | Dev Desk starts the task's agent, by hand or in Auto for queued tasks | Accepted |
| [0019](0019-deep-features-cant-skip-the-architecture-gate.md) | Deep features can't skip the architecture gate; dev:audit checks it | Accepted |
| [0020](0020-impact-and-complexity-are-labels-the-doors-propose.md) | Impact and complexity are labels the doors propose and the developer corrects | Accepted |
| [0021](0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md) | A card opens one dialog, and the panels are the window's edges | Accepted |
| [0022](0022-dev-desk-deletes-a-local-branch-and-nothing-else.md) | Dev Desk deletes a local branch, and nothing else | Accepted, amended by 0023 |
| [0023](0023-the-gate-ran-late-and-took-the-fold-with-it.md) | The gate ran late, and took the fold with it | Accepted, amended by 0024 |
| [0024](0024-a-board-card-is-one-block-and-its-chrome-is-one-modifier.md) | A board card is one block, and its chrome is one modifier | Accepted |
| [0025](0025-a-background-run-belongs-to-the-app-not-the-window.md) | A background run belongs to the app, not the window | Accepted |
