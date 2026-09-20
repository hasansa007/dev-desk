# System model

What dev-desk is made of, which part holds what, and which part wins when two disagree.

[Guide](GUIDE.md) · [Workflow](WORKFLOW.md) · [Commands](COMMANDS.md) · [Diagram](../arch/dev-system.html)

The family is a set of doors — `/dev` and 21 siblings — that run one shared pipeline, [`shared/pipeline.md`](../../shared/pipeline.md), against a repository's git history and its GitHub tracker. The doors write what they learn into files the next run reads back: `PROJECT_MAP.md`, ADRs, dated reports and per-branch checkpoints. Two optional helpers sit beside them: the `dev` CLI, which records checkpoints and computes the board, and four Claude Code hooks, which check tool calls at the points the pipeline names. Dev Desk, a Mac app, reads the same records and shows them.

## The five layers

| Layer | Holds | Written by |
| --- | --- | --- |
| 1 · Truth | git branches and commits; GitHub issues, milestones and PRs | git and GitHub, through the doors |
| 2 · Memory | `PROJECT_MAP.md`, `docs/adr/`, `docs/findings/` and `docs/ideation/` reports, `.dev/<branch>.json` | Phases 10 and 12, `dev:insights`, `dev:findings`, `dev:ideation`, `dev state checkpoint` |
| 3 · Engine | the doors; `shared/pipeline.md`, Phases 0–16; four human gates: 5 discuss · 6 architecture · 14 merge · 16 prod | prose, executed by the agent |
| 4 · Helpers | the `dev` CLI: `state · board · run · project · doctor`; hooks: `branch-guard`, `pr-gates`, `teardown`, `context-load` | `scripts/dev.py`, `hooks/` |
| 5 · Container | Dev Desk's one window, its open projects and its own preferences, never repository truth | the app, in `apps/desk/` |

Each layer is authoritative over every layer numbered above it, so when a checkpoint, a map or the app disagrees with git, git wins.

## The container today

Dev Desk is a native Mac app in `apps/desk/`. It lives in this repository ([ADR 0012](../adr/0012-the-mac-app-lives-in-apps-desk.md)).

It opens two sample projects, StudyHub and dev-desk, which show the whole design with labelled sample data. It also opens real folders. For a real folder it reads git and GitHub directly, through `git` and `gh` ([ADR 0013](../adr/0013-the-app-reads-git-and-github-directly.md)): the board, diffs, commit activity, PR checks, `.dev/` state, and GitHub milestones as Roadmap.

One window holds every project, a strip down its left edge switches them, and **Home** says which one needs you ([ADR 0050](../adr/0050-one-window-holds-every-project-and-the-strip-switches-them.md)). Within a project, five destinations and two edges ([ADR 0021](../adr/0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md)):

- **Board** — every card opens the same dialog over the board, started or not.
- **Roadmap** — GitHub milestones.
- **Findings** reads `docs/findings/` reports (and the older `docs/survey/`); **Ideation** reads `docs/ideation/`. Each asks what a run should focus on, runs the door, and files what you approve through `dev:create-issue`.
- **Insights** is a destination, and unavailable for real projects.
- **Files** down the right edge browses the project's own folder; the bottom edge is a **dock** holding up to four live sessions side by side, each with its own header and ✕ that hides the tile without stopping the session ([ADR 0052](../adr/0052-the-bottom-edge-is-a-dock-that-holds-several-terminals.md)).
- **Terminals is where a task's session lives** — one per task, agent or shell ([ADR 0026](../adr/0026-a-task-has-one-session-and-terminals-is-where-it-lives.md)). It runs in the task's own worktree, and starts only when you start it ([ADR 0017](../adr/0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md)) — or when Auto starts a queued task's agent, in a project where you turned Auto on ([ADR 0018](../adr/0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md)).
- **It writes to the tracker only through a card's bounded Move and Cancel** ([ADR 0014](../adr/0014-dev-desk-replaces-dev-ui.md)). In a repository it creates worktrees, one per task, under the Execution setting's location, and it deletes a **local** branch when you ask it to — the one thing it destroys rather than moves, behind a typed confirmation when commits would be lost ([ADR 0022](../adr/0022-dev-desk-deletes-a-local-branch-and-nothing-else.md)). Clone and Create project each write a new folder. The agents it starts can change files, as they would in your terminal.

## Not built yet

The [container spec](../superpowers/specs/2026-09-11-container-design.md) describes these. None of them exists:

- the shared runner and its jobs, for **sessions in a terminal**. A background run already reports its own state and is answered in the app ([ADR 0025](../adr/0025-a-background-run-belongs-to-the-app-not-the-window.md)); a session in a terminal is still bytes, so the app cannot tell a working agent from one waiting at a gate, or resume an ended session. The direction agreed for closing this is an event sidecar the doors write, in [the next-level record](../superpowers/specs/2026-09-13-next-level-direction-design.md);
- `dev snapshot` and `dev events` (container spec §3);
- agent provider integrations.

## See also

- [`docs/arch/dev-system.html`](../arch/dev-system.html) — these layers as an evidenced diagram, pinned to commit `321fb15`. Open the HTML file: it carries the evidence, recording for each box the file and lines it came from. An exported PNG or SVG carries none of it. The Dev Desk box cites the design brief until a re-pin can cite `apps/desk/`.
- [Container spec](../superpowers/specs/2026-09-11-container-design.md) — the system model, the CLI contract and the first shell.
- [Task continuity spec](../superpowers/specs/2026-09-11-app-cli-task-continuity-design.md) — managed starts and connecting existing work.
- [Navigation spec](../superpowers/specs/2026-09-11-mac-app-navigation-and-insights-design.md) — Findings, Decisions, Insights and settings.
- [Dev Desk design canvas](../design/dev-desk.dc.html)
- [ADR 0012 — the Mac app lives in `apps/desk/`](../adr/0012-the-mac-app-lives-in-apps-desk.md)
- [ADR 0013 — the app reads git and GitHub directly](../adr/0013-the-app-reads-git-and-github-directly.md)
