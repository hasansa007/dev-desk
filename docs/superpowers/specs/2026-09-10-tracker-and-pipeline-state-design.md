# Tracker gates and pipeline state — entries, flows, abilities

**Date:** 2026-09-10
**Status:** design approved, not implemented
**Repo:** `hasansa007/dev-skill` (single-stage — `main` is both pre-prod and prod)
**Reference:** an autonomous multi-agent coding framework (desktop app + Python backend), v2.7.6,
AGPL-3.0. Read at design time; deliberately not named here, and nothing vendored from it.

---

## 1. Goal and constraints

Give this family the capabilities that reference framework has and this one lacks, without giving up the
attended-with-gates model that makes its output trustworthy.

**Licence.** The reference framework is AGPL-3.0. Concepts are borrowed; **no code is copied.** Every file
here is written from the idea, not from the source.

**Evidence.** Comparisons below were taken from that framework's public tree (1,751 files) and from
a working directory it had left in this repo at design time, holding six real specs — so its
behaviour was read rather than inferred. Its `roadmap/roadmap.json` recorded `project_name: "dev-skill"`, 17 features under MoSCoW,
`competitor_analysis_used: true`, of which two were `done` and matched commits `d97fcd5` (#47) and
`4a419b5` (#46).

> **That directory was deleted on 2026-09-10** — it held a live `CLAUDE_CODE_OAUTH_TOKEN` and
> `GITHUB_TOKEN` in an ungitignored `.env` (never committed; `git log -S` confirmed the history was
> clean). Its 71 tracked files remain recoverable from history at `7c6cc52` and earlier. The
> untracked remainder, including that roadmap, is gone. **Claims sourced to it below are recorded
> here and cannot be re-verified from the working tree** — they are stated as observations made at
> design time, not as live citations.

### Out of scope, deliberately

| Not building | Why |
|---|---|
| Unattended autonomy | `shared/pipeline.md`: *"Automatic means 'do not ask between mechanical steps.' It never means unattended."* Four gates stop on purpose |
| Worktree parallelism | `shared/pipeline.md:986` forbids `git worktree add` when the IDE opens each worktree in its own window |
| Graphiti / graph memory | needs a DB, embeddings and API keys — wrong shape for a markdown family |
| Linear, GitLab | `gh` only |
| AI merge-conflict resolution | conflicts are a judgment gate, not a mechanical one |
| Competitor analysis | produces claims nothing in the repo can verify — the opposite of how every other door works |
| Changelog generation | deferred, not rejected |
| An `error` board column | a blocker stops and asks; `ORPHANED` is the git-derived analogue and cannot lie |

---

## 2. Doors: 17 → 20 (19 after Stage 4; `dev:insights` would be the 20th)

| Door | Status | Replaces |
|---|---|---|
| `dev:kanban` | new | `dev:issues` (deleted) |
| `dev:ideation` | new | — (**added beside** `dev:survey`, which stays) |
| `dev:roadmap` | new | — |
| `dev:insights` | new, **low priority** | — |

This is the largest the family has been, against the *Simplicity First* guiding principle. Accepted
knowingly.

### Routing changes (`SKILL.md` Entry 1)

- Bare `/dev` routes to **`dev:kanban`** (was `dev:issues`).
- The one-word guard gains `kanban`, `ideation`, `insights`, `roadmap` **and keeps `issues` and
  `survey` as retired-name aliases.** Not optional: the guard already carries a scar from exactly
  this, when `trim` → `comment-budget`. A retired name dropped from the guard means `/dev issues`
  cuts a branch called "issues".

### Retirement tail

`dev:issues` is referenced in 7 other files (`README.md`, `SKILL.md`, `shared/entry.md`,
`skills/launch`, `skills/arch`, `skills/survey`); `dev:survey` in 11 (adds
`documentation/COMMANDS.md`, `documentation/CONTRIBUTING.md`, `shared/pipeline.md`). Some are
**functional**, not prose: `dev:survey` Phase 9 depends on `dev:issues` Phase 5's ordering to
justify setting priority labels at all.

### The one clause that cannot be ported

`dev:issues` `## Never` opens with *"Never cut a branch, never edit an issue, never start work.
**Read-only is the whole contract.**"* `dev:kanban` breaks that by design. Everything else in that
list survives verbatim; this clause is **rewritten into bounded-write rules**, and it is the single
place where the port can quietly become a downgrade.

---

## 3. Two axes

The reference framework tracks board position and build position separately
(`apps/frontend/src/shared/types/task.ts`):

```ts
type TaskStatus   = 'backlog' | 'queue' | 'in_progress' | 'ai_review'
                  | 'human_review' | 'done' | 'pr_created' | 'error';
type TaskLogPhase = 'planning' | 'coding' | 'validation';
```

### Axis 1 — column

| Column | Evidence | Authority |
|---|---|---|
| `backlog` | open issue, no branch | git |
| `queue` | member of the **active milestone** | written |
| `in_progress` | branch with unmerged commits, no PR | git |
| `ai_review` | phases 12–13 | state file |
| `pr_created` | `gh pr view` → OPEN | git |
| `human_review` | `reviewDecision` | git |
| `done` | PR merged + issue closed | git |

### Axis 2 — phase (advisory)

| Phase | Pipeline phases |
|---|---|
| `planning` | 1–8 · context → investigation → discuss → architecture → plan → breakdown |
| `coding` | 9–10 · implement → pre-PR quality |
| `validation` | 11–13 · verification → docs → code review |

### Precedence rule

> **Git is authoritative; phase state is advisory.** Columns git can see are recomputed every run
> and cannot be stale. `planning`/`coding`/`validation` come from a file that *can* lie. Where they
> disagree, **git wins and the card says the state file disagreed** — never the reverse.

Without this, a card reading "validation" for a branch deleted last week is worse than no card.

### Not states

- **ORPHANED** — unmerged commits whose issue is closed, or mapping to no issue. An always-rendered
  anomaly row, never a column. (2026-08-05: two branches carried 5 and 2 unmerged commits, both
  issues CLOSED.)
- **DEFERRED** — `epic-leftover`. Parked, not queued.
- **CURRENT** — orthogonal marker. A card is `in_progress` *and* current.

---

## 4. Backing

- **No GitHub Project v2 board.** No `project` token scope, nothing provisioned per repo, board
  reconstructable from scratch anywhere.
- **`queue` = active-milestone membership.** `dev:roadmap` §6 writes milestones anyway, so
  milestone-awareness costs nothing extra. Note milestones are currently a void: the only
  occurrence of "milestone" in the real files is `SKILL.md:90`, which fetches the field and never
  uses it.
- **Everything else derived** from `git` / `gh` plus `.dev/<branch>.json`.

A chosen queue order **overrides** Phase 5's automatic ordering. Phase 5 ranks what *could* be next;
the queue records what was *decided*, and a decided order is never silently re-sorted by priority
label.

---

## 5. State artifact

`.dev/<branch>.json` — `repo`, `branch`, `base`, `tier`, `phase`, `phases_completed[]`,
`attempts[]` (approach, outcome, error), `head_sha`, `updated_at`.

**Where it lives:** in the **target repo** being worked on, not in `dev-skill`. The family is
installed once and drives many repos; state belongs with the work.

**Filename:** branch names contain slashes (`feature/tracker-and-pipeline-state`), which would silently
create nested directories. The branch is slugified — `/` → `-` — and the true branch name is stored
in the `branch` field. `dev state read` resolves by field, never by filename.

**Tracked or ignored:** **ignored.** `.dev/` is per-machine working state; git is authoritative for
everything that matters, so a lost `.dev/` costs a phase number and nothing else. Committing it
would put a churning JSON file in every PR diff and invite merge conflicts on a file no human
reads. Stage 1 appends `.dev/` to the target repo's `.gitignore` — and must handle the repo that
has no `.gitignore`, and the repo where it is already ignored globally.

**Mechanism (approach C):** `shared/pipeline.md` calls the CLI at each phase boundary;
`hooks/pr-gates.sh` refuses PR creation when the file is missing or its `head_sha` disagrees with
git. Discipline writes, the machine catches — and the gate lands at the one moment being wrong
costs anything: before a PR carries a false record.

Unlocks, from one file:

- the **`/dev --continue`** resume entry — closing the gap `SKILL.md` already admits:
  *"Phases 1–8 have no sibling on purpose — they pass reasoning rather than artifacts, so there is
  nothing to hand a fresh session."*
- **attempt history**, so a retry stops re-learning what already failed
- `dev:audit` reading a real record instead of reconstructing phases from tool calls

---

## 6. The `dev` CLI — optional, with prose fallback

**Precedent:** `scripts/compliance_auditor.py` is 609 lines of **stdlib-only** Python (`argparse`,
`json`, `os`, `re`, `subprocess`, `sys`, `typing`) — no `requirements.txt`, no venv. A CLI in that
style needs `python3` and nothing else.

**Split:**

| Kind | Examples | Home |
|---|---|---|
| Deterministic | resolve repo · resolve base · one `gh issue list` · classify columns · parse the epic task list · `rev-list --count` · order P1→P2→slice→age · state I/O · verify against git | **the CLI** |
| Judgment | investigation · discuss-before-building · architecture alternatives · adversarial verification · writing code · review reasoning | **prose** |

`dev:issues` Phases 3–5 already read like an algorithm because they are one. Moving them kills a
real bug class — the 2026-08-05 scar where a bare `#N` grep computed an epic as `1/5` instead of
`0/4`.

**Optional, not required.** Each door calls `dev` when it is on PATH and falls back to the prose
algorithm when it is not. This preserves `SKILL.md`'s claim — *"plain markdown over `git` and
`gh`"* — and keeps Claude Code, Codex and Antigravity all working. Cost: two paths that must not
drift; mitigated by both being generated from this spec.

**Commands (v0):** `dev state checkpoint|read|verify` · `dev doctor` · `dev board [--json]`.

`board` is pure at its core — issues plus per-issue git facts in, columns out — so every
classification rule is tested against fixtures rather than a live tracker. The fixture that matters
most reproduces the 2026-08-05 shape exactly: an epic body with four `- [ ] #N` children plus the
same unrelated roadmap issue referenced twice in prose. A bare `#N` grep returns five and reports
`1/5`; the task-list parse returns four and reports `0/4`.

**It never writes to another repo's `.gitignore`.** `doctor` reports that `.dev/` is unignored and
prints the line to add; appending it would be this family writing into a repo it does not own,
which the write-boundary rule forbids without an explicit yes naming that repo.

**Test convention already exists** — verified 2026-09-10. `test-projects/compliance/test_compliance_auditor.py`
(7 tests) and `test-projects/rollback/test_rollback_engine.py` (5 tests) are 474 lines of stdlib
`unittest`, run directly as `PYTHONPATH=. python3 <file>`, and **all 12 pass**. Stage 1 follows that
convention rather than inventing a harness: one test file per script, stdlib only.

⚠️ **But nothing ran them.** `ci/pr-gates.yml` is **deliberately uninstalled** — its own header says
so, because its `required-sections` job would fail every PR opened against this repo, which are not
pipeline runs. This repo's real CI was one workflow, `.github/workflows/line-budget.yml`, installed
on its own after four consecutive ceiling breaches. No workflow ran a test, so the suite passed only
when someone remembered to — the failure mode `dev:audit` exists to catch elsewhere.

**Fixed 2026-09-10:** `.github/workflows/tests.yml`, installed on its own per the same convention.
It *discovers* `test-projects/*/test_*.py` rather than listing them, so it keeps covering whatever
is added next, and pins Python 3.9 — what macOS ships as system `python3`, and the version these
stdlib-only scripts must actually run on.

---

## 7. Portability and distribution

**Blocker (fixed 2026-09-10).** 14 files hardcoded a clone-specific path — `SKILL.md` alone 9 of 33
occurrences. The pipeline's first instruction was to read a file under `~/Developer/skills/…`,
which resolves on exactly one machine.

**What it is NOT.** Making these relative would revert documented scar tissue. `dev:survey` Phase 2
says it outright: *"the absolute path, because this skill runs inside somebody else's repo, where a
bare `shared/entry.md` resolves to a file that does not exist."* `dev:arch` Phase 0 carries the
same. Absolute was the fix; the home-directory prefix was the accident.

**Fix applied:** the **install** path, not the clone path. `install.sh` symlinks this repo into each
CLI's skills directory under the fixed name `dev`, so `~/.claude/skills/dev/` resolves identically
on any machine. 31 occurrences across 13 files swapped; the convention is documented once in
`SKILL.md` and once in `shared/entry.md`, with the Codex and Antigravity roots named.

Verified on 2026-09-10: all three symlinks present, and `shared/entry.md`, `shared/pipeline.md`,
`mobile/MASTER_PROMPT.md`, `web/FEATURE_PROMPT.md` and `hooks/pr-gates.sh` all resolve through the
new root.

**Consequence, accepted:** a clone that has never been installed has no root, so `install.sh`
becomes required rather than convenient. Stated in both notes.

**Also:** `gh repo view` → `visibility: PRIVATE`, `licenseInfo: null`, no `LICENSE` file. Public
distribution needs both; without a licence nobody may legally use it even once public.

**Already solved:** `install.sh` installs into Claude Code, Codex and Antigravity, reads
Antigravity's registered path from config rather than assuming, and refuses to clobber a real
directory.

**Deferred:** public-vs-private and packaging (Claude Code plugin vs multi-CLI clone). Stage 0
serves both equally, so waiting costs nothing. They are not exclusive — a `dev` CLI works alongside
multi-CLI install; only narrowing to a Claude Code plugin gives up the Codex and Antigravity
support that already works.

---

## 8. Door phase lists

### `dev:kanban` — 8 phases

| Phase | Origin |
|---|---|
| 1 — Arguments | ported: *(none)* · `stats` · `all` · label filter. **New:** `move` / `cancel` / `delete` |
| 2 — Resolve the repo | **verbatim**, with the boundary rule and its 2026-08-05 scar |
| 3 — Fetch once | **verbatim** — one `gh issue list`; auth failure must never render as an empty board |
| 4 — Classify | **verbatim** — 4.1 epic-parent-not-startable (task-list parse, never a bare `#N` grep), 4.2 unmerged measured against the base, 4.3 unmerged work on a closed issue |
| 4.4 — Decorate *(new)* | overlay advisory phase; git wins, and the card says so |
| 5 — Order NEXT | **verbatim** — P1→P2→P3, unlabelled after P3, slice order, oldest `updatedAt` |
| 6 — Render, then ask | **verbatim** + a phase column; ends by asking, never by listing |
| 6b — Empty NEXT | **verbatim** — read the repo's own recorded gaps; never invent work |
| 7 — Act *(new)* | the write set (§9) |
| 7.1 — Epic children *(new)* | enumerate before cancel/delete → cascade · re-parent · orphan-and-report |

`IN FLIGHT` keeps its name rather than becoming `BUILDING` — it is the name in the scar tissue and
in three other files, and it is more accurate.

### `dev:ideation` — 9 phases

**Split, not a port.** `dev:survey` keeps defects + architecture unchanged; `dev:ideation` is a new door owning the opportunities hunt alone and cross-referencing `dev:survey` for the shared protocol (Phases 2, 3, 4, 5, 8) rather than duplicating it.

| Phase | Change |
|---|---|
| 1 — Arguments | `--bugs` / `--arch` kept; **add `--opportunities`** (perf, vulnerabilities, quality). Default all three |
| 2 — Resolve repo, read what is tracked | verbatim |
| 3 — Discover flows from evidence | verbatim |
| 4 — Fan out, one surveyor per flow | + opportunity prompts |
| 5 — Verify adversarially | **verbatim, never skipped.** Two independent checkers per finding, each prompted to refute, never seeing each other's verdict; disagreement resolves to PLAUSIBLE; REFUTED findings listed with their refutation |
| 6 — Architecture pass | verbatim — count before recommending; produces an ADR or an epic |
| 7 — Write the report | `docs/ideation/<date>.md` |
| 8 — Walk it through | verbatim, incl. *never show the fix before asking for theirs* |
| 9 — Offer to file | verbatim — max 10 per run, priority labels, conflicting-vs-blocking. **Cross-reference retargets to `dev:kanban` Phase 5** |

Opportunities multiply findings, and Phase 5 costs two checkers each — the declared estimate needs
re-baselining.

### `dev:roadmap` — 7 phases

| Phase | |
|---|---|
| 1 — Arguments | *(none)* → propose · `themes` · horizon filter |
| 2 — Read what exists | open milestones, epics, backlog, **and rejected themes** — extend, never duplicate |
| 3 — Discover from evidence | the repo's recorded gaps (`dev:kanban` 6b's greps), `PROJECT_MAP.md` `ORPHANS & PENDING`, prior `docs/ideation/` reports |
| 4 — Propose themes | ranked, **ranking marked as a claim** with a because-clause |
| 5 — Confirm | nothing reaches GitHub without a yes |
| 6 — Write | milestones + epic parents via `dev:create-epic`. **Parent only** — slices cut at Phase 5 |
| 7 — Render and hand off | to `/dev #N` or `dev:kanban` |

### `dev:insights` — 6 phases *(low priority)*

| Phase | |
|---|---|
| 1 — Arguments | a question; *nothing* → print the four seeds |
| 2 — Resolve the repo | boundary rule |
| 3 — Answer from evidence | `file:line` citations, never from memory |
| 4 — Route | architecture → `dev:arch`; quality/security → `dev:ideation`; what-next → `dev:roadmap`. Hand off rather than half-doing it |
| 5 — Fold into `PROJECT_MAP.md` | durable findings only |
| 6 — Ask next | never end silently |

That framework needs an Insights panel because it is a desktop app with no chat. The value here is
not the chat — it is that answers stop dying at session end.

---

## 9. Write set

| Tier | Command | Reversible | Guard |
|---|---|---|---|
| Move | `gh issue edit` — labels, milestone, assignee | yes | none beyond the run |
| Cancel | `gh issue close --reason "not planned"` + a why-comment | yes (`gh issue reopen`) | confirm once |
| Delete | `gh issue delete` | **no** | hard gate |

**Delete's hard gate:** confirm against the printed `owner/repo#N`; **refused outright** when a
merged PR references the issue or when open children exist. Never passes `--yes` unprompted.

Two reasons delete is worse here than "it is permanent": the Phase 14 overlay writes `Closes #N`
into merged PR bodies, so deleting dangles that reference in git history forever; and epics have
children, which `DEFERRED` (literally *epic-leftover*) would silently absorb.

---

## 10. Lifecycle terminators

**Nothing in the family currently closes an epic parent.** `dev:create-epic`'s template writes a
`## Done when` described as *"observable, epic-level — true only when every child is closed"* — the
epic states its own completion condition and **no door evaluates it.** Phase 14 writes `Closes #N`
for the child; the parent stays open forever, and the board degrades as it gets more use.

```
dev:roadmap §6  ─▶  milestone M + epic parents E1…En (childless)
                         │  a childless epic IS startable (4.1)
                    /dev #E1 ─▶ Phase 5 decomposes → children `- [ ] #C`
                         │  E1 drops out of NEXT, shows as progress 0/k
                    dev:kanban offers C1 (slice order)
                         │
                    /dev #C1 … Phase 14 merge, `Closes #C1`
                         ▼  NEW: last-sibling check → close E1
                         ▼  NEW: last-epic check → close M
                    dev:ideation ─▶ docs/ideation/<date>.md ─▶ dev:roadmap §3
```

- **Close-the-parent lives in `dev:kanban`** — it already computes `0/4` and is now a writing door.
  At `n/n` it offers to close the parent; when a milestone's epics all close, it offers to close
  the milestone. `dev:pre-prod` gets a one-line nudge at the moment the last sibling merges.
- **Rejected themes** are filed, closed `not planned` with the why-comment (`dev:kanban`'s cancel
  path exactly), labelled, and read back by `dev:roadmap` §2 — so a declined direction is not
  re-proposed next quarter. One source of truth, no new store.

---

## 11. Stages

| Stage | Ships | Blocks |
|---|---|---|
| **0 — Portability** | ✅ paths → install path (31 occurrences, 13 files). `LICENSE` deferred with publishing | **everything** — doors written after are portable from birth |
| **1 — CLI v0** | ✅ complete. `dev state` · `doctor` · `board` (`scripts/dev.py`, stdlib, 41 tests) · CI runs all 4 suites · `pr-gates.sh` asks on STALE state | Stage 2's phase column; `--continue` |
| **2 — `dev:kanban`** | ✅ `skills/kanban/SKILL.md` (8 phases); `dev:issues` deleted; 7 cross-references swept; guard keeps `issues` as a retired-name alias | — |
| **3 — `dev:ideation`** | ✅ `skills/ideation/SKILL.md` (9 phases, opportunities only). `dev:survey` **kept**, restored byte-identical after a same-day merge-and-revert; ADR 0008 records both | — |
| **4 — `dev:roadmap`** | ✅ `skills/roadmap/SKILL.md` (7 phases). Read commands verified live against an empty tracker; `epic` and `roadmap-declined` labels confirmed absent here, which is why Phase 6 reads `gh label list` rather than assuming | — |
| **5 — `dev:insights`** | ✅ `skills/insights/SKILL.md` (6 phases). Answer → route → fold durable into `PROJECT_MAP.md`; `map` audits drift without writing | — |
| **6 — `dev run`** | CLI shells out to `claude`/`codex`/`antigravity` — the headless/CI story | needs Stage 1 |
| **later** | publish: public + packaging | — |

One branch and PR per stage. **This is a single-stage repo** — the Phase 14 merge *is* the
production merge, Phase 16 is skipped, and its secrets pre-flight moves up to Phase 14.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| 19 doors against *Simplicity First* | accepted knowingly; `dev:insights` deprioritised |
| Phase state lies between checkpoints | §3 precedence rule + `pr-gates.sh` refusal |
| `gh issue delete` is permanent | §9 hard gate; refused on merged-PR reference or open children |
| CLI and prose paths drift | both generated from this spec; `dev doctor` reports version skew |
| A retired door's scar tissue is lost in the port | §2 names it as a hard requirement, not a hope |
| New artifacts leak project identity | every file stays project-agnostic: no repo names, issue numbers, branch names or issue titles |
| Tests exist but CI never runs them | Stage 1 wires `ci/pr-gates.yml` to execute the suite before the CLI is load-bearing |

---

## 13. Cost

≈ **6 new files** (4 `SKILL.md`, the CLI, `LICENSE`) · **2 deleted** · **22 edited** — 18 carrying
cross-references to the retired doors, 14 carrying the hardcoded path, overlapping.

Counts re-verified 2026-09-10 against a clean tree.
