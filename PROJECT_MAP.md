---
type: map
reviewed: 2026-09-21
---

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
| Tests | stdlib `unittest`, one file per script under `tests/<area>/test_*.py`, run as `PYTHONPATH=. python3 <file>` |
| Mac app | `apps/desk/` — Dev Desk, a native macOS app: SwiftUI with AppKit where needed, macOS 14+, Swift 5 mode. `project.yml` generates the Xcode project with xcodegen (gitignored, not committed); `DeskCore` is the local Swift package — models, sample data, the git/GitHub reader, task folders and shell state — tested with `swift test --package-path apps/desk/DeskCore` (see [ADR 0012](docs/adr/0012-the-mac-app-lives-in-apps-desk.md)). One dependency, SwiftTerm 1.11.2, in the app target only; DeskCore has none ([ADR 0016](docs/adr/0016-dev-desk-embeds-a-terminal-with-swiftterm.md)). **SwiftTerm is on its way out**: [ADR 0036](docs/adr/0036-agents-run-over-a-protocol-and-the-terminal-leaves-the-app.md) reverses 0016 — task agents move to the Agent Client Protocol and the pty leaves the app, taking the dependency with it. The client is hand-rolled in DeskCore, which stays dependency-free |
| CI | `.github/workflows/` — `line-budget.yml` (sums `shared/pipeline.md` + `shared/pipeline/*.md` against the ceiling and count in `docs/guide/CONTRIBUTING.md`; it measured the index alone from the 2026-09-14 split until #90 and was red on every run for a week), `tests.yml`, and `desk.yml` (path-filtered to `apps/desk/**` and `shared/board-rules.json`, which DeskCore's conformance test reads: DeskCore's `swift test` and an `xcodebuild` of the app; first run green on PR #50). Each installed **on its own**; `hooks/pr-gates.yml`, beside the `pr-gates.sh` hook that mirrors it, is a template for *other* repos and is deliberately never installed here |
| Install | `install.sh` symlinks the clone into each CLI's skills dir as `dev`, maintains the family's root at `~/.claude/.dev-root`, and links `scripts/dev.py` as the `dev` command into `~/.local/bin` (or `~/bin`) when one is already on `PATH`. A **plugin** install creates no per-CLI link, so `context-load.sh` maintains the same root from its SessionStart hook ([ADR 0054](docs/adr/0054-the-install-root-is-one-hidden-symlink-not-a-skills-directory.md)). **`apps/desk/install.sh` is a different thing**: it builds Dev Desk Release, ad-hoc signed, into `~/Applications` — the bundle you actually open, which is not the DerivedData one Xcode builds (ADR 0024's context) |

**Paths inside the family are the INSTALL ROOT** (`~/.claude/.dev-root/…`), never the clone path.
Absolute on purpose: doors run inside somebody else's repo, where a relative `shared/entry.md`
resolves to nothing.

**Agent CLIs with verified non-interactive invocations:** `claude -p`, `codex exec`. Antigravity
and Gemini are not supported — see ORPHANS.

## SYSTEM_FLOW

**One pipeline; every door is an entry into it at a different floor.**

```
bare /dev ─▶ dev:board (board) ─▶ name an issue ─▶ /dev #N
#N | free text ─▶ Phases 1-8 (reason) ─▶ 9-10 (build) ─▶ 11-13 (gates) ─▶ 14 (PR ▸ merge)
```

**Four gates stop for a human on purpose:** Phase 5 (discuss), 6 (architecture), 14 (merge),
16 (prod). Everything between them runs without asking.

**The stocking loop** — what puts work on the board:

```
dev:findings  defects + architectural drift ─┐
dev:ideation  perf / security / quality      ├─▶ docs/{findings,ideation}/<date>.md
                                             │
dev:roadmap   reads those + the repo's own recorded gaps + ORPHANS & PENDING below
              └─▶ milestone (= dev:board's QUEUE) + epic parents, PARENTS ONLY
                  └─▶ /dev #E ─▶ Phase 5 cuts slices ─▶ children
                      └─▶ dev:board 7.3 closes the epic, then the milestone
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
GitHub, `docs/findings/`, `docs/ideation/`, `.dev/` state — and runs three things inside a repository: a
door, from Findings or Ideation, and — each in the task's own worktree — a task's shell and its agent,
started by you from the task's dialog or by Auto in a project where you turned it on (ADRs 0017,
0018). Its two sample projects demo the whole design on labelled sample data; a real opened
folder shows only what it can actually read, with the reason next to anything it can't yet (see
ORPHANS).

## ORPHANS & PENDING

**Doors that exist but have never been exercised.** Each says so in its own `## Scar tissue`:

| | |
|---|---|
| `dev:board` Phase 7 | **first writes 2026-09-12**: six children of #59 closed as completed with per-criterion evidence, two held open with the gap named, the epic commented at 6/8. Move, cancel and delete are still unproven, as is the QUEUE column (this repo has no milestone) |
| `dev:ideation` | never run |
| `dev:roadmap` | never written a milestone |
| `dev:insights` | never run; this file is the first thing its Phase 5 would maintain |
| `dev:code-review` | **run twice 2026-09-12**: over #69 after the fact (15 findings, 1 narrowed, 1 sub-point refuted) and over the branch that fixed them. The `--quick` path is still designed, not observed; the security pass ran **by hand** both times, because `security-review` reads pending changes and the first diff was already merged |

**Repo state that blocks parts of the design:**

- **No `roadmap-declined` label**, so the declined-theme round trip is untested. `epic`,
  `impact:high|medium|low`, `complexity:high|medium|low` and `plan-not-final` exist since
  2026-09-12, created for epic #59 (ADR 0020).
- **No `project` token scope**, so `dev project`'s live path — listing, field discovery and item edits — has never run. Its planning core is fixture-tested.
- **QUEUE fills since a milestone exists** — the board of 2026-09-20 put 3 of 11 open issues in it,
  resolved as the oldest open milestone because none has a due date.
- **`dev board` reaches `pr_created`/`human_review` since 2026-09-20.** `cmd_board` reads open pull
  requests once and attaches one per issue, by head branch or by a closing line in the body — Dev
  Desk's two rules (`BoardBuilder.branch`, `closedIssues`), so the app and the CLI now agree on an
  issue with an open PR. A draft is In progress in both. Still unobserved on a live tracker: this
  repo's one open PR closes no issue, so both columns are covered by fixtures only.

**Dev Desk (`apps/desk/`), not built yet:**

- **Runner-dependent surfaces work only in the sample projects** — Insights' answers, and a task's
  agent list in a project whose agents are not installed. A real opened project shows each as
  unavailable, with the reason (ADR 0013). Real shells and real agents are live: the task's dialog
  starts either, in that task's own worktree (ADRs 0017, 0018).
- **`dev snapshot`, `dev jobs` and `dev events`** (container spec §3) are not built. The app starts
  and stops agents as terminal processes (ADR 0018), but it can't tell a working agent from a
  waiting one, resume an ended session, or answer a door from its own UI.
- **Auto starts from Ready for dev**, which holds the active milestone's issues and every card moved
  there by hand (ADR 0035); a repo with neither gives Auto nothing to start (ADR 0018).
- **The board rules are duplicated**, in `apps/desk/DeskCore/Sources/DeskCore/Local/BoardBuilder.swift`,
  mirroring `scripts/dev.py` by hand (ADR 0013) — but the mirror is no longer held by memory: `shared/board-rules.json`
  is a **registry** of the seven shared rules as 49 cases, and both suites fail on a rule they do not bind
  (ADR 0055), so a rule added to one reader alone cannot go green. Measured at 42 inputs before it was written:
  zero divergences, so this is a ratchet rather than a repair. It covers rules, never column vocabulary, and
  `resolve_base`'s declared divergence stays out. A rule that exists in one reader and is never registered is
  still invisible. The app's board has
  since grown columns of its own (`Ready for dev` and the stored stages, ADR 0035) that `dev board`
  deliberately does not show. Both measure a branch
  against `origin/<base>`, never a local copy that can lag. One rule is Dev Desk's alone: a branch
  still at a merged pull request's head goes to Done, which covers squash merges. `dev board` reads
  no merged pull requests, so it can't apply it.
- **The agent prompt is duplicated.** `AgentLaunch.prompt` mirrors `scripts/dev.py`'s `build_prompt`
  byte for byte (ADR 0018), so a change to one needs both. The **install root** it is built from is no
  longer duplicated inside the app: `InstallRoot` is DeskCore's one authority and every builder resolves
  through it, mirroring `skill_root`'s preference for `~/.claude/.dev-root` with a fallback to the
  per-CLI link for a machine installed before ADR 0054. It is still one copy per language — #89 covers
  the cross-language authority and the CI check that would have caught this. The template drifting
  while the argument fed to it moved is exactly what "byte for byte" could not watch (#88).
- **`docs/arch/dev-system.html` needs a re-pin.** Its Container node still cites the design brief
  rather than `apps/desk/` (merged in #50), and its `scripts/dev.py` citations moved when `dev ui`
  was removed (ADR 0014). The folder reorganisation (ADR 0015) moved none of its cited paths, so
  the re-pin no longer waits on it.
- **The Notifications settings pane stores values** (`desk.notifyDecisions`/`notifyCompletion`/
  `notifyFailures`) that nothing reads yet — no notification is posted. Execution's
  `desk.worktreeLocation` is live: task worktrees are created there (ADR 0017).
- **Dev Desk never removes a worktree it created.** They stay under the worktree location until
  `git worktree remove <path>` (ADR 0017). It does now delete a local **branch** from its card (ADRs 0022,
  0023): `-d` always runs first, `-D` only after git itself has refused, and only a plain branch card offers it —
  a pull request's head is not abandoned. The worktree such a branch sits in is a separate thing, and git
  refuses the delete while one holds it.
- **An epic with sub-issues is not recognised as decomposed.** `BoardBuilder.isDecomposedEpic` and
  `scripts/dev.py`'s `is_startable` both look for `- [ ] #N` checklist lines in the parent's body,
  while `shared/pipeline.md` Phase 5 forbids checkbox slices and requires the `sub_issues` API. So a
  parent filed the way the pipeline demands — #59 is the first — is offered as startable on the
  board and in `dev board`. Both readers need the sub-issue list; a two-reader fix, as ADR 0013
  predicted for every board rule.
- **A fork PR's head is still matched by name for what the board shows.** Its branch line, its
  Activity and Changes, the pipeline-state lookup and the rule that hides a same-named local branch
  all use `headRefName`. So a fork PR from `someone:main` shows the local `main`'s commits. Its shell
  is safe: fork heads get no branch and open at the project root (ADR 0017).
- **No Ideation or PROJECT_MAP view.** `/dev:ui` rendered `docs/ideation/` reports and
  `PROJECT_MAP.md`'s sections as pages until it was retired on 2026-09-11 (ADR 0014). Dev Desk's
  Findings reads only `docs/findings/` (and the older `docs/survey/`) and Insights is unavailable for real projects, so both are read
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
