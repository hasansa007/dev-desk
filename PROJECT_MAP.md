# PROJECT_MAP

The pipeline's memory. Phase 1 loads it; Phase 4 skips its exploration fan-out when this file
already covers the area — so **an entry here that is wrong costs more than one that is missing.**

Maintained by `dev:insights` (Phase 5), and by Phase 10 of any `/dev` run.
Created 2026-09-10.

---

## TECH_STACK

**This repo is a skill family, not an application.** It ships prose that agents execute, plus a
small deterministic helper.

| | |
|---|---|
| Doors | 21 × `skills/<name>/SKILL.md`, plus the root `SKILL.md` |
| Shared contracts | `shared/entry.md` (workspace + write boundary) and `shared/pipeline.md` (17 phases; 11–14 each have a door) — the files nearly every door reads |
| Flow files | a file one flow reads lives with that flow ([ADR 0015](docs/adr/0015-files-live-with-the-flow-that-reads-them.md)): `platforms/web/` and `platforms/mobile/` hold each platform's `MASTER_PROMPT.md`, `FEATURE_PROMPT.md` and Phase 10/11/14 overlays (`pipeline-web.md`; `pipeline-{ios,android,kmp}.md`); `skills/prod/prod-secrets*.md` is the production secrets pre-flight |
| Helper CLI | `scripts/dev.py` — **stdlib only**, Python 3.9-compatible. `state` · `board` · `run` · `doctor` · `project` |
| Compliance | `skills/audit/compliance_auditor.py` — stdlib only |
| Hooks | `hooks/*.sh` — bash + `jq`, installed into `~/.claude/hooks/` |
| Tests | stdlib `unittest`, one file per script under `test-projects/<area>/test_*.py`, run as `PYTHONPATH=. python3 <file>` |
| Mac app | `apps/desk/` — Dev Desk, a native macOS app: SwiftUI with AppKit where needed, macOS 14+, Swift 5 mode. `project.yml` generates the Xcode project with xcodegen (gitignored, not committed); `DeskCore` is the local Swift package — models, sample data, the git/GitHub reader — tested with `swift test --package-path apps/desk/DeskCore` (see [ADR 0012](docs/adr/0012-the-mac-app-lives-in-apps-desk.md)) |
| CI | `.github/workflows/` — `line-budget.yml`, `tests.yml`, and `desk.yml` (path-filtered to `apps/desk/**`: DeskCore's `swift test` and an `xcodebuild` of the app; first run green on PR #50). Each installed **on its own**; `ci/pr-gates.yml` is a template for *other* repos and is deliberately never installed here |
| Install | `install.sh` symlinks the clone into each CLI's skills dir as `dev`, and links `scripts/dev.py` as the `dev` command into `~/.local/bin` (or `~/bin`) when one is already on `PATH` |

**Paths inside the family are the INSTALL path** (`~/.claude/skills/dev/…`), never the clone path.
Absolute on purpose: doors run inside somebody else's repo, where a relative `shared/entry.md`
resolves to nothing.

**Agent CLIs with verified non-interactive invocations:** `claude -p`, `codex exec`. Antigravity
and Gemini are not supported — see ORPHANS.

## SYSTEM_FLOW

**One pipeline; every door is an entry into it at a different floor.**

```
bare /dev ─▶ dev:kanban (board) ─▶ name an issue ─▶ /dev #N
#N | free text ─▶ Phases 1-8 (reason) ─▶ 9-10 (build) ─▶ 11-13 (gates) ─▶ 14 (PR ▸ merge)
```

**Four gates stop for a human on purpose:** Phase 5 (discuss), 6 (architecture), 14 (merge),
16 (prod). Everything between them runs without asking.

**The stocking loop** — what puts work on the board:

```
dev:survey    defects + architectural drift ─┐
dev:ideation  perf / security / quality      ├─▶ docs/{survey,ideation}/<date>.md
                                             │
dev:roadmap   reads those + the repo's own recorded gaps + ORPHANS & PENDING below
              └─▶ milestone (= dev:kanban's QUEUE) + epic parents, PARENTS ONLY
                  └─▶ /dev #E ─▶ Phase 5 cuts slices ─▶ children
                      └─▶ dev:kanban 7.3 closes the epic, then the milestone
```

**Two axes on the board.** Columns come from `git`/`gh` and cannot be stale. The
`planning`/`coding`/`validation` phase comes from `.dev/<branch>.json` and **can** lie — so git wins
every disagreement, and no state file means no phase claim at all.

**This repo is SINGLE-STAGE.** No `staging` or `develop` on the remote, so `main` is both pre-prod
and prod: the Phase 14 merge *is* the production merge, Phase 16 is skipped, and its secrets
pre-flight moves up into Phase 14.

**`docs/` is tracked here** (changed 2026-09-10) so an ADR can be part of the diff that introduces
its decision. Skills still probe `git check-ignore -q docs/` per repo, because the answer differs.

**The container.** Dev Desk (`apps/desk/`) reads what the doors and `dev` already wrote — git,
GitHub, `docs/survey/`, `docs/adr/`, `.dev/` state — and starts no agents itself. Its two sample
projects demo the whole design on labelled sample data; a real opened folder shows only what it can
actually read, with the reason next to anything it can't yet (see ORPHANS).

## ORPHANS & PENDING

**Doors that exist but have never been exercised.** Each says so in its own `## Scar tissue`:

| | |
|---|---|
| `dev:kanban` Phase 7 | no write has been made through it — move, cancel and delete are unproven, as is the QUEUE column |
| `dev:ideation` | never run |
| `dev:roadmap` | never written a milestone |
| `dev:insights` | never run; this file is the first thing its Phase 5 would maintain |
| `dev:code-review` | never run — the `--quick` path, the spec-compliance table and the re-verification trigger are designed, not observed |

**Repo state that blocks parts of the design:**

- **No `epic` label** in this tracker, so `dev:kanban` 4.1's epic-progress logic cannot fire.
  `dev:roadmap` Phase 6 offers to create it; nothing creates it silently.
- **No `roadmap-declined` label**, so the declined-theme round trip is untested.
- **No `project` token scope**, so `dev project`'s live path — listing, field discovery and item edits — has never run. Its planning core is fixture-tested.
- **0 open issues, 0 milestones** — every board render so far has been of an empty tracker.
- **`dev board` never reaches the `pr_created`/`human_review` columns.** `cmd_board`
  (`scripts/dev.py:371-383`) builds each issue's `facts` dict with only `unmerged` and
  `phase_group` — it never sets `facts["pr"]`, so `classify`'s PR branch (`facts.get("pr")`) is
  always empty and those two columns are dead code. Dev Desk's board (ADR 0013) does receive PR
  data and reaches Review correctly, so for an issue with an open PR the app says Review while
  `dev board` says In progress or Backlog. A `dev.py` fix; out of this branch's scope.

**Dev Desk (`apps/desk/`), not built yet:**

- **Runner-dependent surfaces work only in the sample projects** — the agents list, the terminal
  dock, decisions waiting on an answer, Insights' answers, and tracker updates from the app. A real
  opened project shows each as unavailable, with the reason (ADR 0013).
- **`dev snapshot`, `dev jobs` and `dev events`** (container spec §3) are not built — the app cannot
  start, stop or answer a door yet.
- **The board rules are duplicated**, in `apps/desk/DeskCore/Sources/DeskCore/Local/BoardBuilder.swift`,
  mirroring `scripts/dev.py` by hand (ADR 0013) — a rule change needs both.
- **`docs/arch/dev-system.html` needs a re-pin.** Its Container node still cites the design brief
  rather than `apps/desk/` (merged in #50), and its `scripts/dev.py` citations moved when `dev ui`
  was removed (ADR 0014). The folder reorganisation (ADR 0015) moved none of its cited paths, so
  the re-pin no longer waits on it.
- **The Notifications and Execution settings panes store values**
  (`desk.notifyDecisions`/`notifyCompletion`/`notifyFailures`, `desk.worktreeLocation`) that nothing
  reads yet — no notification is posted, no worktree is created at the configured path.
- **No Ideation or PROJECT_MAP view.** `/dev:ui` rendered `docs/ideation/` reports and
  `PROJECT_MAP.md`'s sections as pages until it was retired on 2026-09-11 (ADR 0014). Dev Desk's
  Findings reads only `docs/survey/` and Insights is unavailable for real projects, so both are read
  as files until the app adds those screens.

**Deferred deliberately:**

- **`LICENSE` and publishing** — repo is `PRIVATE` with `licenseInfo: null`. Public distribution
  needs both; without a licence nobody may use it even once public.
- **The CLI never edits a *target* repo's `.gitignore`.** It does not need to: the first write into
  `.dev/` also writes `.dev/.gitignore` (`*`), inside the family's own folder, so `.dev/` — phase
  state — ignores itself. State written by hand, without the CLI, lacks it; `dev doctor` still
  reports that case.
- **Changelog generation** — deferred, not rejected.

**Known environment gaps:**

- **Antigravity CLI is not installed**, though `install.sh` links skills into its directory. The
  binary on `PATH` is a shim that reports the real CLI missing, so `dev run --agent antigravity` is
  refused rather than guessed. Gemini has no confirmed non-interactive invocation either.
- **Two of the three evidenced diagrams have an orphaned pin.** `docs/arch/dev-family.architecture.json`
  (pinned `90bcc4fa…`) and `docs/arch/dev-journey.architecture.json` (pinned `f1bc5fcb…`) each cite
  a commit that is not an ancestor of `main` or this branch — an earlier squash merge likely dropped
  it from history while the commit object itself is still present locally (`git cat-file -t`
  succeeds), which is why `archify validate` still reads `ok` today. Neither pin resolves for a
  fresh clone, or after this machine's next `git gc`. Not caused by PR #50: none of the 115 files
  it changed intersect either diagram's cited paths. Needs a re-pin at a reachable commit;
  `docs/arch/` is out of this task's touch-list. **`dev-family` needs a redraw, not only a re-pin:**
  it still draws a `dev:ui` component citing `skills/ui/SKILL.md`, and its CLI note lists `ui` —
  both retired 2026-09-11 (ADR 0014). README's caption now gives the family's count, 21 doors; the
  diagram still draws 22 until the redraw drops `dev:ui`. **Both IRs also cite files that moved on
  2026-09-11** ([ADR 0015](docs/adr/0015-files-live-with-the-flow-that-reads-them.md)): `dev-family`
  cites the iOS, Android and web overlays and the secrets pre-flight at their old `shared/` paths, now
  under `platforms/mobile/`, `platforms/web/` and `skills/prod/`; `dev-journey` cites the secrets
  pre-flight. Each IR must name the new paths before it can be re-pinned at a commit after the move.
