---
name: dev
description: >
  Personal developer workflow for features AND bugs on personal projects.
  Accepts: GitHub issue URL or number (#123, github.com/.../issues/N), or a plain feature
  title / bug description.
  Also trigger when user says "start feature", "work on issue", "new branch for",
  "investigate this issue", "fix this bug", or pastes a GitHub issue URL.
allowed-tools: [gh, git]
---

# Dev — Personal Workflow

GitHub issues, features and bugs for personal projects.

The rules below are CLI-agnostic — plain markdown over `git` and `gh`. Only the invocation
(`/dev:<door>`), the `.claude-plugin` namespace and `hooks/` are Claude Code's.

---

## Where these paths point

Every `~/.claude/skills/dev/...` path in this family is the **install** path, not the clone path.
`install.sh` symlinks this repo into each CLI's skills directory under the fixed name `dev`, so the
path resolves the same on every machine regardless of where the repo was cloned:

| CLI | Root |
|---|---|
| Claude Code | `~/.claude/skills/dev/` |
| Codex | `~/.codex/skills/dev/` |
| Antigravity | its registered skills path (`install.sh` reads it from config) — else `~/.agents/skills/dev/` |

**The paths stay absolute on purpose.** These doors run inside somebody else's repo, where a bare
`shared/entry.md` resolves to a file that does not exist — `dev:survey` Phase 2 and `dev:arch`
Phase 0 both carry that scar. Absolute is the fix; a home-directory prefix was the accident.

A clone that has never been installed has no such root. Run `install.sh` first.

---

## Workspace Config

**Lives in `~/.claude/skills/dev/shared/entry.md`** — repo auto-detect, pre-prod branch resolution,
prod branch resolution, and the single-stage detection. It is shared with every `dev-*` sibling,
so it is defined once there and never duplicated here.

---

## Entry 1 — Input Detection & Routing

> **Numbering:** these two are ENTRY steps, not pipeline phases. They run before
> `shared/pipeline.md` starts, and are numbered separately so they never collide with the
> pipeline's own Phase 1 (Context Load). Order is: Entry 1 → Entry 2 → pipeline Phase 1 → Phase 2 → …

| Input | Route |
|---|---|
| **Nothing at all** | **Entry 0 — Orient**: detect where this repo actually is, then offer the two or three doors that fit it |
| `#N`, `github.com/.../issues/N`, GitHub issue URL | **GitHub** flow |
| A bare family name — `run`, `prod`, `pre-prod`, `rollback`, `audit`, `verify`, `docs`, `review`, `comment-budget`, `trim`, `kanban`, `issues`, `survey`, `ideation`, `roadmap`, `insights`, `code-review`, `arch`, `ui` | **Confirm the handoff** — see the guard below |
| Any other free text | **Generic** flow |

### The empty-input row is a guard, not a convenience

**2026-08-05 — bare `/dev` had no defined behaviour.** With no empty row, it fell toward "any other
free text", whose Entry 2 says *"the argument text is the feature description / seed"* — and with no
argument there is no seed. The outcome was whatever got improvised, up to cutting a branch at
Phase 3 for a feature nobody asked for.

That is the same failure as the one-word guard below, one step further out: the guard catches
`/dev run`, and left `/dev` — strictly more ambiguous — unhandled. Giving empty input a **defined,
read-only** answer turns the emptiest input into the most useful one, and the worst case is a
question instead of a branch.

**2026-09-10 — the fixed destination was wrong for half the repos it met.** Empty input routed
straight to `dev:kanban`. That is the right answer for a repo with a stocked tracker and useless for
the other three cases: a fresh install where nothing is configured, a codebase whose tracker is
empty, and a run that stopped halfway and wants resuming. A board rendering `0 open` is a true
answer to a question the developer did not ask. Entry 0 keeps the guard — still read-only, still
never a branch — and picks the destination from what is actually there.

---

## Entry 0 — Orient (bare `/dev` only)

**One detection pass, then two or three offers. Never a list of twenty-one doors.**

```bash
git rev-parse --show-toplevel                      # a repo at all?
git log -1 --format=%H                             # any commits?
git remote get-url origin                          # a remote?
gh issue list --state open --limit 1 --json number # a reachable tracker, and is it stocked?
git branch --format='%(refname:short)'             # branches to resume
ls .dev/*.json                                     # a run that checkpointed
```

`dev board --json` and `dev state read` supply the same facts when the CLI is installed. **A failed
query and an empty result are different answers** — say which you got.

Then match the FIRST situation that applies:

| Situation | Detected by | Offer |
|---|---|---|
| **1 · Work in flight** | `.dev/<branch>.json` exists, or a branch carries commits not in the base | **Resume it.** Name the branch, the phase it reached, and what comes next. `/dev --continue`, or the door for that phase |
| **2 · The board has work** | tracker reachable and has open issues | `dev:kanban` — the board, then pick one |
| **3 · Code, but an empty tracker** | commits exist, tracker reachable and empty | `dev:survey` (what is wrong) · `dev:ideation` (what is worth doing) · `dev:roadmap` (group it into milestones) |
| **4 · A fresh or empty project** | no commits, or no remote, or `gh` not authenticated | Say exactly what is missing and how to fix it, then offer `/dev <description>` to build the first thing |

**Rules this inherits and must not lose:**

- **Read-only.** Entry 0 detects and asks. It never cuts a branch, never edits an issue, never
  starts work — naming a choice hands off to the door that owns it.
- **Never render another repo's state** (`shared/entry.md`, write boundary). An empty tracker here
  is the answer; another repo's fuller one is a sentence you may say, never a board you render.
- **Never invent work to fill situation 3.** `dev:kanban` 6b's rule applies: surface only what the
  repo already wrote down, and *"this repo records no gaps"* is a complete answer.
- **Situation 1 outranks the rest.** Unfinished work is the thing most likely to be forgotten, and
  the thing most expensive to rediscover.

### Guard — a command-shaped argument is not a feature title

`/dev` takes no subcommands, so a bare word falls through to "any other free text" and gets read as
a **feature name**: `/dev run` would branch `feature/run` and start building a feature called
"run". Observed 2026-08-04.

Before routing to Generic, STOP if the argument is:

- **a family name** — `run`, `prod`, `pre-prod`, `rollback`, `audit`, `verify`, `docs`, `review`, `comment-budget`, `kanban`, `survey`, `ideation`, `roadmap`, `insights`, `code-review`, `arch`, `ui`, with or without the
  `dev-` prefix. Name the sibling it maps to and confirm:
  *"`/dev run` isn't a subcommand — did you mean `/dev:launch`?"*
- **a RENAMED family name.** `trim` is still the advertised trigger (*"trim the comments"*) after the
  door became `comment-budget` on 2026-09-07, so `/dev trim` must map, not fall through:
  *"`/dev trim` isn't a subcommand — did you mean `/dev:comment-budget`?"* A rename that drops the
  old name from this guard while leaving it in the triggers turns it into a feature title.
  **`issues` is the same case** after the board became `dev:kanban` on 2026-09-10 — "show the
  issues" is still how anyone asks for it, so `/dev issues` must map:
  *"`/dev issues` isn't a subcommand — did you mean `/dev:kanban`?"*
- **a single word with no verb and no object** (`deploy`, `test`, `fix`). Far likelier a mistyped
  command than a feature brief.

Never open a branch on a one-word argument. **Stop on Ambiguity** applies at the front door, not
only at Phase 2 — the cheapest place to catch a wrong turn is before the branch exists.

---

## Entry 2 — Fetch Context

### GitHub Issue

Auto-detect repo:
```bash
git remote get-url origin
# SSH:   git@github.com:owner/repo.git  → owner/repo
# HTTPS: https://github.com/owner/repo  → owner/repo
```

Fetch issue:
```bash
gh issue view <N> --json title,body,labels,assignees,milestone
```

Detect issue type from labels: `bug` → Bug investigation flow; `enhancement` / `feature` → Feature flow.

### Generic (feature title)

No external fetch. The argument text is the feature description / seed.
Read local context: `CLAUDE.md`, `README.md`, `docs/`, `.spec/`.

---

## Phase 14 Additions (GitHub) — overlay, not a separate phase

Applied ON TOP of the pipeline's Phase 14 when the source is a GitHub issue:

- Add `Closes #N` at the end of the PR body
- Apply labels from the source issue where applicable
- Repo is auto-detected from `git remote get-url origin`

---

## The `dev-*` family

`dev` is the full run. Each sibling is a door into the same pipeline at a later floor — use one
directly when the work already exists and only that phase is needed:

| Skill | Phase | Input | Use when |
|---|---|---|---|
| `dev:create-bug` | 0 | a description | "file this bug" — creates the issue, does not fix it |
| `dev:create-issue` | 0 | a description | "capture this feature/task" |
| `dev:create-epic` | 0 | a description | "this is a big one" — files the PARENT only |
| `dev:verify` | 11 | a branch | "does this branch actually work?" |
| `dev:docs` | 12 | a diff | "are the ADRs and docs current?" |
| `dev:code-review` | 13 | a branch | "review this before it becomes a PR" — verified findings, spec compliance, security |
| `dev:pre-prod` | 14 | a branch | "PR and merge this to pre prod" |
| `dev:review` | 15 ↺ | a PR number | "changes requested" — loops back to 14 |
| `dev:prod` | 16 | pre-prod + prod branches | "promote to production" |
| `dev:rollback` | 16 ↺ | a broken commit or release | "rollback production" — classifies change, proposes recovery, pauses for approval |
| `dev:launch` | — | a project to launch | "run the app" — a TOOL, not a phase |
| `dev:launch-kill` | — | a project to stop | "kill the dev server", "free the port" — `launch` inverted |
| `dev:shots` | — | a running app | "screenshot the app", "app store screenshots" — capture, iOS/Android/web |
| `dev:comment-budget` | — | a repo or a path | "trim the comments" — existing code to the doc budget; reports unless `--apply` |
| `dev:arch` | — | a system to draw | "draw the architecture", "map this system" — verifiable diagram; renders via Archify |
| `dev:survey` | — | an existing app | "what's wrong with this app" — defects + architectural drift, files the confirmed |
| `dev:ideation` | — | an existing app | "what could we improve" — perf/security/quality opportunities, files the confirmed |
| `dev:roadmap` | — | the repo's own evidence | "what should we build next" — themes → milestones + epic parents; **makes the QUEUE exist** |
| `dev:insights` | — | a question | "how does this work?" — cited answer, routes to the owning door, folds durable findings into `PROJECT_MAP.md` |
| `dev:ui` | — | a repo | "open the ui" — rebuilds only the stale `ui/` pages, says why, opens the board |
| `dev:kanban` | — | the repo's tracker | "what should I work on?" — the board, plus bounded card writes; bare `/dev` offers it when the tracker has work |

They all read the same `shared/pipeline.md`; none of them copies it. **Phases 1–8 have no sibling on
purpose** — they pass reasoning rather than artifacts, so there is nothing to hand a fresh session.
Phase 0 sits on the other side of that seam: it runs *before* any reasoning exists, takes only a
description, and produces an issue number. That is why it can be a door when Phase 4 cannot.

---

## Shared Pipeline

1. Read `~/.claude/skills/dev/shared/entry.md` — workspace + base-branch resolution, shared with
   every `dev-*` sibling.
2. Read `~/.claude/skills/dev/shared/pipeline.md` and execute all phases from it, incorporating the
   Phase 14 additions defined above.

The pipeline's Phase 2 detects the stack and routes to the matching platform pipeline automatically.

---

## Architecture Prompts (Conditional)

Apply only when `ARCHITECTURE.md` is **missing** from the repo root (first feature on a new project), or when the user explicitly asks to revisit architecture.

### Mobile

| Detected stack | Variant | Prompt location |
|---|---|---|
| `*.xcodeproj` / `Package.swift` only | A — iOS only | `~/.claude/skills/dev/mobile/MASTER_PROMPT.md` |
| `build.gradle*` + Android manifest only | B — Android only | `~/.claude/skills/dev/mobile/MASTER_PROMPT.md` |
| `androidApp/` + `iOSApp/` + `shared/` (KMP) | C — iOS + Android + KMP | `~/.claude/skills/dev/mobile/MASTER_PROMPT.md` |

### Web

| Detected stack | Prompt location |
|---|---|
| `package.json` → Next.js / React / Vue | `~/.claude/skills/dev/web/MASTER_PROMPT.md` |

### Per-Feature Prompts

For every feature (regardless of whether ARCHITECTURE.md exists), use the matching feature prompt as the seed for Phase 7 (Plan Output):

| Stack | Feature prompt |
|---|---|
| Mobile (iOS / Android / KMP) | `~/.claude/skills/dev/mobile/FEATURE_PROMPT.md` |
| Web (Next.js / React / Vue) | `~/.claude/skills/dev/web/FEATURE_PROMPT.md` |

Do not invoke architecture or feature prompts for trivial changes (typos, copy edits, dependency bumps).
