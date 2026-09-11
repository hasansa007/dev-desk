# 0013 — The app reads git and GitHub directly, until `dev snapshot` exists

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `feat/dev-desk-mac-app-design`

## Context

The container spec's contract (§3.1, `dev snapshot --json`) is the intended long-term read: one
document, one process, replacing separate board/roadmap/reports/insights reads. It is not built.
The developer decided in this session, alongside ADR 0012, that the first build reads real
projects now rather than waiting — sample data alone was rejected for opened folders.

## Decision

`LocalGitDataSource` (`apps/desk/DeskCore/Sources/DeskCore/Local/`) reads `git` and `gh` directly
for an opened folder and mirrors `scripts/dev.py`'s board logic by hand: `GitReader` gathers the
same facts `dev.py` gathers per branch, `BoardContext.column(for:...)` (in `BoardBuilder.swift`)
re-implements `classify`, `BoardContext.tasks()` re-implements `build_board`'s column assembly, and
`ActiveMilestone.resolve` re-implements `resolve_active_milestone` line for line, including its
same-day-tie refusal to pick silently.

**One deliberate difference.** `dev.py`'s `resolve_base` checks only the remote: the first of
`staging`/`develop`/`main`/`master` present under `origin/`, else the current branch
(`scripts/dev.py:57-66`). `GitReader.resolveBase` adds a step for a repo with **no origin**: before
falling back to the current branch, it checks the same four names among **local** branches
(`apps/desk/DeskCore/Sources/DeskCore/Local/GitReader.swift`, `resolveBase`, and
`GitOutput.preferredBase(among:)`). Without that step, a locally-created repo with a `main` branch
and a feature branch checked out would resolve its own base to the current (feature) branch —
every other branch's "unmerged" count would be computed against a moving target that is itself
unmerged, which is the "nothing in flight" failure: the board would show no work in progress even
while a real base branch sits right there, untracked because it never left this machine. Dev Desk
opens exactly this shape of folder (a `create-project` result, or any repo cloned without a
remote), so the gap could not be left as a shared limitation.

**Both measure a branch against origin's copy of the base** when the remote has one
(`GitReader.resolveBase`; `origin_ref` in `scripts/dev.py`), never a local branch of that name. A
local copy lags behind pull requests merged on GitHub and counts their work as unmerged: until
2026-09-12 both used it whenever it existed, and a merged task showed as in progress.

## Rejected

- **Sample data only, for opened folders too.** The developer chose real reads for this build
  instead — a folder you open is a real project, not a demo, and showing sample numbers against a
  real path is worse than showing nothing.
- **Wait for `dev snapshot --json` (container spec §3.1 / §7 deliverable B).** Blocks the whole app
  on a CLI contract that does not exist yet, with no date. The five other flows this branch ships —
  Board, Findings, Roadmap, Decisions, sample projects — do not need to wait for it.
- **Shell out to `dev board --json` now, as a stopgap.** Inspected `scripts/dev.py`'s
  `cmd_board`/`build_board`: its JSON rows carry only `number`, `title`, `priority`, `column`, and
  optional `phase`/`epic` fields — no PR number, no branch name, and no merged/"Done" column, all of
  which the Board and Parallel screens need. It also requires `python3` and an installed `dev` on
  `PATH`, which a freshly-cloned or unconfigured machine may not have. A second, independent path
  would still be needed for those cases, so shelling out would have added a dependency without
  removing the duplication it was meant to avoid.

## Consequences

- **The board rules now exist twice** — `scripts/dev.py` and
  `apps/desk/DeskCore/Sources/DeskCore/Local/BoardBuilder.swift` — so a rule change (a new column, a
  changed priority order, a new base-branch candidate) must be made in both.
  `documentation/CONTRIBUTING.md`'s "Where to extend" table says so.
- **Tests pin both copies independently:** `test-projects/state/test_dev_board.py` for
  `scripts/dev.py`; `BoardBuilderTests.swift` and `ActiveMilestoneTests.swift` for the Swift mirror.
  Neither test suite reads the other language's source, so a divergence is caught only if both are
  updated and both still pass — there is no automatic cross-check.
- **The migration is one seam.** `ProjectDataSource` (`apps/desk/DeskCore/Sources/DeskCore/Data/ProjectDataSource.swift`)
  is the only place a project's data source is chosen (`DataSources.make`). When `dev snapshot
  --json` exists, replacing `LocalGitDataSource`'s git/gh calls with one snapshot read changes one
  conforming type behind that seam; `SampleDataSource` and every screen that consumes
  `ProjectSnapshot` are unaffected.

## Evidence

Read side by side: `scripts/dev.py:57-66` (`resolve_base`), `scripts/dev.py:267-282` (`classify`),
`scripts/dev.py:285-315` (`build_board`), `scripts/dev.py:333-344` (`resolve_active_milestone`)
against `apps/desk/DeskCore/Sources/DeskCore/Local/GitReader.swift` (`resolveBase`, `baseCandidates
= ["staging", "develop", "main", "master"]`), `BoardBuilder.swift` (`column(for:)`,
`BoardContext.tasks()`), and `ActiveMilestone.swift` (`resolve`) — same candidate order, same
column rules, same tie refusal, the one no-origin fallback added and named above.
`dev board --json`'s row shape confirmed by reading `cmd_board`'s call to `build_board` directly;
no PR number, branch name or "done" column is produced.

## Later (2026-09-11)

`resolve_base` moved to `scripts/dev.py:57-66` when `dev ui` was retired
([ADR 0014](0014-dev-desk-replaces-dev-ui.md)); the Decision above keeps the citation as merged.
