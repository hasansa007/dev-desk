# 0014 — Dev Desk replaces `/dev:ui`

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `fix/desk-security-and-retire-dev-ui`

## Context

`/dev:ui` (`skills/ui/SKILL.md`) and the `dev ui` subcommand of `scripts/dev.py` rendered four pages
into `.dev/ui/` — board, roadmap, ideation, insights — plus an index linking them. `dev ui --serve`
served those pages on `127.0.0.1`. On the served board, dragging a card between QUEUE and BACKLOG
edited its milestone, and dropping it on CANCEL closed it as *not planned*; `plan_board_move`
planned both writes. The door, the subcommand and the server all landed in `321fb15` on 2026-09-11.

Dev Desk (`apps/desk/`, ADR 0012) shows the same board and the roadmap from the same git and GitHub
reads, for sample projects and for real opened folders (ADR 0013). That made two UIs for one job.
The developer decided on 2026-09-11 that Dev Desk replaces `/dev:ui`, and asked for the removal now.

## Decision

The developer retired `/dev:ui` for Dev Desk. `skills/ui/` is deleted. So is `dev ui`, along with
every function only it used: the four page renderers and the index, the staleness check, the
`--serve` server and its token check, and `plan_board_move`. The three test files that covered them
are deleted too.

Two things stay:

- **The name, in the front-door guard.** The root `SKILL.md`'s Entry 1 guard maps `ui` to a
  retirement message, so `/dev ui` gets an answer instead of becoming a feature title.
- **The one board rule that only `dev ui` applied.** Without `--milestone`, `dev board` now resolves
  the active milestone by `dev:roadmap`'s rule, using `resolve_active_milestone` unchanged. So
  `dev:board`'s QUEUE fills without the flag. `dev board --json` reports the choice as
  `active_milestone` and `active_why`. When the milestone read fails, the output says so instead of
  reporting "no milestone".

## Rejected

- **Keep both.** Two UIs for one job drift apart. The board rules already exist twice, in
  `scripts/dev.py` and in Dev Desk's `BoardBuilder.swift` (ADR 0013). A third renderer of the same
  columns would be one more place for a rule change to be missed.
- **Keep `dev ui` until Dev Desk covers everything**, meaning the ideation and insights pages and
  the drag. The developer chose to retire it now. The gaps this leaves are listed below and in
  `PROJECT_MAP.md`'s ORPHANS & PENDING.

## Consequences

- **Card moves and cancels go through `/dev:board`, in conversation, with no drag.** Its Phase 7
  Move and Cancel tiers are unchanged; only the served board that also drove them is gone. The
  container spec's future `dev board move` (§3.4) can re-add `plan_board_move` as a CLI verb. The
  refusals it needs: git-derived columns, epic cancels, delete, and a cancel with no reason.
- **The Ideation and PROJECT_MAP pages are gone** until Dev Desk adds those screens. Dev Desk's
  Findings reads only `docs/survey/`, and its Insights is unavailable for real projects. The
  sources are still readable as files: `docs/ideation/<date>.md` (with its `.json` twin) and
  `PROJECT_MAP.md`.
- **Linux and Windows users have no UI, including the Codex and Antigravity installs.** `dev ui`
  needed only `python3` and a browser; Dev Desk is a macOS app. Those users keep the text board
  (`/dev:board`, `dev board`) and `dev project`'s mirror into GitHub Projects.
- **`.dev/` still holds pipeline state:** `.dev/<branch>.json` from `dev state checkpoint`, and the
  `.dev/.gitignore` the CLI writes when it first creates the folder. Two tests used to pin that
  self-ignore through `dev ui`. They now pin it through `dev state checkpoint`, in
  `test-projects/state/test_dev_state.py`.
- **`docs/arch/dev-family.architecture.json` still draws a `dev:ui` component.** The component
  cites `skills/ui/SKILL.md` at a pin (`90bcc4fa…`) that was already orphaned, and the diagram's CLI
  note lists `ui`. It needs a redraw, not only a re-pin. That is recorded in ORPHANS & PENDING,
  because `docs/arch/` is outside this change.
- **ADR 0013's `scripts/dev.py` line citations were refreshed.** The ranges for `resolve_base`,
  `classify` and `build_board` moved up two lines when the served board's two imports (`hmac`,
  `secrets`) were removed, and `resolve_active_milestone` moved beside `cmd_board`. None of the four
  functions changed.

## Evidence

```
python3 scripts/dev.py --help
→ usage: dev [-h] {state,board,run,project,doctor} ...

wc -l scripts/dev.py
→ 1286 before, 746 after — 28 names removed, none still referenced

python3 scripts/dev.py board        # this repo: no open milestone
→ ## hasansa007/dev-skill — 0 open
  QUEUE is empty — no open milestone; dev:roadmap sets one

for f in test-projects/*/test_*.py; do PYTHONPATH=. python3 "$f" 2>&1 | tail -2; done
→ compliance 7/7 · rollback 5/5 · board 34/34 · project 16/16 · run 16/16 · state 17/17
```

The 65 tests in the three deleted files covered only `dev ui`, apart from six. The four
active-milestone tests moved to `test_dev_board.py`, next to four new ones for `dev board`'s default
resolution. The two `.dev/.gitignore` tests moved to `test_dev_state.py`.
`git grep -n -E 'dev:ui|dev ui|/dev:ui|skills/ui|\.dev/ui' -- . ':!docs/arch/*.html'` now matches
only the Entry 1 guard, this ADR and its index row, dated notes in the container spec, the ORPHANS
& PENDING entries, and `docs/arch/dev-family.architecture.json`.
