# Dev Family — Shared Entry Contract

Read by `dev` and by every `dev-*` sibling **before anything else**. One source of truth for
workspace resolution and for which pipeline sections always load.

> **The family's own repository is exempt.** When the resolved repo is `dev-skill` — the source of
> these doors — the Phase 11–14 gates do not apply to changes made in it: a repo cannot be governed by
> the rules it defines, and the loop has no end. Build with `apps/desk/install.sh`, look at the
> result, commit to the working branch. See that repo's `CLAUDE.md`. Everywhere else, the gates hold
> exactly as written below.

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
`shared/entry.md` resolves to a file that does not exist — `dev:findings` Phase 2 and `dev:arch`
Phase 0 both carry that scar. Absolute is the fix; a home-directory prefix was the accident.

A clone that has never been installed has no such root. Run `install.sh` first.

---

## Workspace Resolution

```
GitHub repo: AUTO-DETECTED at runtime via `git remote get-url origin`
             Parse SSH (git@github.com:owner/repo.git) or HTTPS (https://github.com/owner/repo)
             Strip .git suffix → owner/repo

Pre-prod branch: AUTO-DETECTED — never assume. Resolve in this order:
  1. The repo's release runbook (`docs/deploy-and-staging.md` or similar) — its
     branch model WINS over anything below.
  2. First that exists on the remote: `staging` → `develop` → `main` / `master`
     git branch -r --format='%(refname:short)'
  3. Not a git repo → current HEAD

Prod branch: the branch whose merge RELEASES PRODUCTION.
  1. The runbook wins.
  2. Else `main` / `master`.

  Worked example — a two-stage repo: pre prod = `staging`, prod = `main`. A feature PR
  based on `main` never deploys; merging to `main` DEPLOYS PROD. Confirm both before acting.
```

If the two resolve to the same branch, the repo has a **single-stage model**: Phase 14's merge
already reaches production. Say so explicitly, and skip Phase 16 — **except its secrets pre-flight**
(`skills/prod/prod-secrets.md`), which moves to Phase 14 and runs before that merge. It is bound to the
merge that releases production, not to a phase number; skipping it here is how it missed the very
incident it was written for.

## The resolved repo is a WRITE boundary

Reading elsewhere is a mistake; **writing elsewhere is a different category of mistake.** Before any
commit, branch, push, PR or merge:

1. **State the target repo and branch, by name, before acting** — `owner/repo`, not "the app repo".
   A phrase like "the other checkout" is not a repo identifier and cannot be checked.
2. **Never write to a repo other than the resolved one without an explicit yes** naming that repo.
   Authorization to fix something is not authorization to fix it *anywhere*.
3. **Work on a NEW BRANCH, never directly on the main line**, so there is a reviewable object before
   anything lands — and **cut it from the pre-prod branch resolved above, not from whatever is
   checked out.**
4. **Cut it in a WORKTREE of its own, and never switch the project folder's branch.** Every task and
   every process — a `/dev` task, a findings or ideation run, a rollback — gets its own branch in its
   own folder. The project folder stays on its base: it is what the board, the reports and every new
   worktree read as "the project", and whatever else is open in it (a person, another agent) is working
   on the branch it was left on. `git switch`, `git checkout <branch>` and `gh pr checkout` in a project
   folder are blocked by a hook where one is installed; in a linked worktree they are fine.

A branch cut from another unmerged branch inherits that branch's commits, and they become part of
your diff, your PR and your review. Nothing warns you: the name is right, the tests pass, and
`git status` reports the branch you are **on**, never the one you came **from**.

```bash
git fetch origin
git worktree add --no-track -b <name> ~/.devdesk/wt/<repo>-<task> origin/<pre-prod>   # --no-track matters, see below
cd ~/.devdesk/wt/<repo>-<task>                     # and work here, not in the project folder
git log --oneline origin/<pre-prod>..HEAD          # empty = you are AT the base; anything = you are not
```

A branch that already exists gets its worktree the same way — `git worktree add ~/.devdesk/wt/<repo>-<task>
<name>` — or is used where it is already checked out (`git worktree list`). The folder's untracked env
files (`.env.local` and the like) are not carried by git; copy them in before running the app.

> **2026-09-17 — one folder, three owners.** A task's branch was switched into the project folder and its
> work left uncommitted there for days; a findings run then switched the same folder to its own branch
> and back to cut a report; later something switched it to production's branch, and a "behind base"
> banner offered to merge the base into it. Every screen that reads the folder — the report list, the
> board's base comparison — showed whichever branch happened to be checked out. A branch per task in a
> worktree per task, and a folder that never moves, removes the whole class.

**`--no-track` is not optional.** Without it the new branch's upstream is the *base*, and git's first
suggestion for a bare `git push` becomes `git push origin HEAD:<pre-prod>` — which lands your commits
on the pre-prod branch and skips Phases 12 and 13 entirely. With it, git suggests
`--set-upstream origin <name>`, which is what you want. Verified on git 2.50.1.

**When the dependency is real** — an epic's slice that needs its sibling's unmerged code — cut from
that branch deliberately, say so in the PR body, and target the PR at it. The rule forbids the
*accidental* dependency, not the chosen one.

> **2026-08-31 — two doors, one base, and a PR that carried the wrong one.** A branch for a new door
> was cut while another door's branch was checked out, so it inherited that door's commit. The cost
> arrived at the PR: the diff carried the other work, so the PR was targeted at *that* branch to keep
> it readable — then that branch moved, the PR went `CONFLICTING`, and the repair was a rebase, a
> conflict resolution, a force-push and a retarget. One `--no-track` cut from the base would have
> avoided all of it. **Two branches from one base are independent; a branch from a branch is a
> dependency nobody agreed to.**

> **2026-08-05 → 06 — read-boundary written, write-boundary missing.** A boundary rule was added to
> `dev:board`'s predecessor after it rendered another repo's board — read-only, and the user still had to ask
> *"what branch, what repo?"*. Hours later the same session opened and merged **two PRs** into that
> other repo on a two-word instruction, without naming the repo first. Both were docs-only; both
> reached `main` via a promotion, and in that repo merging to `main` auto-deploys production.
>
> The first rule was scoped to rendering a board, so it did not cover the case that matters. **A
> boundary that only governs reads is not a boundary.** The user's correction was explicit: verify
> the origin before changing anything, and at minimum cut a branch.

## A result is not a claim — say what it MEANS

`dev:launch` 2.0 rule 2 covers the **empty** result: never report absence without printing where you
looked. This is its other half, and the harder one. A non-empty result that answers a **narrower
question than you asked** is plausible on its face, so nothing prompts a second look — and it gets
reported as the broader answer.

Before any command's output becomes a claim, check three things:

1. **Scope limiter** — does the command bound its own coverage? `-maxdepth`, `head`, `--limit`, a
   path prefix, or a regex that **enumerates** cases where it should match a class. If it does:
   remove the limit, or report the number as a **floor** and name what bounds it.
2. **Ambiguous encoding** — does any output value carry two meanings? A blank field that means both
   *"in sync"* and *"not configured"*; a `0` that means both *"none"* and *"not measured"*.
   Disambiguate with a second query **before** labelling.
3. **Predicate substitution** — is what you measured what you are claiming? Absence of code is not
   staleness of docs.

Then state it in the form **`<result> — from <command>, which covers <domain>`**.

> **2026-08-06 → 08 — four instances in one session, each reported confidently, each wrong.**
> A depth-limited `find` returned **21** build schemes and was reported as the repo's total; the
> real figure is **1130**, and the small number made "present them all and ask" look viable when it
> is not. A sweep whose pattern *enumerated* identifier forms and omitted two of them reported
> **clean** while five identifiers stood. A branch check read a field that is blank for both *in
> sync* and *no upstream*, and rendered **76** branches as unpushed when **67** were fine. A doc
> audit measured whether the code existed and claimed the docs were stale; both docs already
> carried accurate status.
>
> None of these errored. Each returned a plausible **non-empty** answer to a question slightly
> smaller than the one asked. The empty-result rule existed throughout and could not fire, because
> nothing was ever empty. Three of the four happened after that rule was written, by the person who
> wrote it.
>
> **No hook can enforce this** — it is about interpretation, not a tool boundary. It raises the
> floor; it does not seal it.

---

## What to load from `shared/pipeline/`

`shared/pipeline.md` is now an index; the phases live as one file per phase under
`~/.claude/skills/dev/shared/pipeline/`, and every file named below is relative to that folder —
these doors run inside somebody else's repo, where a bare relative path resolves to nothing, so the
folder is spelled absolutely once here and by basename everywhere else. **A door loads only the files
its row below names** — that is the rule the whole split exists to state.

**Always, for every entry point** — these are cheap and they govern how you work:

| Section | File | Why |
|---|---|---|
| Guiding Principles | `00-principles.md` | Simplicity First, Stop on Ambiguity, Surgical Editing |
| Right-Size the Process | `00-principles.md` | pick Light / Standard / Deep and SAY which |
| Universal Rules | `18-output-and-universal-rules.md` | commit hygiene, no AI attribution, no worktrees in this repo |

**Conditionally** — a sibling loads these only when its own phase actually consumes them.
Right-Size applies to the preamble too: loading discovery for a read-only gate is the ceremony
this pipeline exists to refuse.

| Section | File | Load it when | So: |
|---|---|---|---|
| **Phase 1 — Context Load** | `02-phase-01-context-load.md` | your phase reads or changes code, and needs to know the system | `dev:verify`, `dev:review` |
| **Phase 2 — Tech Stack & Discovery** | `03-phase-02-tech-stack.md` | **your phase has a platform overlay.** `pipeline-<platform>.md` defines additions to Phases 10, 11 and 14 ONLY — no other phase has one, so no other phase needs the stack detected | `dev:verify` (11), `dev:pre-prod` (14) |

| Sibling | Phase | Loads |
|---|---|---|
| `dev` | 1–16 | every file under `~/.claude/skills/dev/shared/pipeline/` except `01-phase-00-filing.md` — the item already exists by the time it runs |
| `dev:create-bug` | 0 | `00-principles.md` **minus Right-Size** + `18-output-and-universal-rules.md` + `01-phase-00-filing.md` |
| `dev:create-issue` | 0 | `00-principles.md` **minus Right-Size** + `18-output-and-universal-rules.md` + `01-phase-00-filing.md` |
| `dev:create-epic` | 0 | `00-principles.md` **minus Right-Size** + `18-output-and-universal-rules.md` + `01-phase-00-filing.md` |
| `dev:verify` | 11 | `00-principles.md` + `18-output-and-universal-rules.md` + `02-phase-01-context-load.md` + `03-phase-02-tech-stack.md` + `12-phase-11-verification.md` → platform pipeline |
| `dev:pre-prod` | 14 | `00-principles.md` + `18-output-and-universal-rules.md` + `03-phase-02-tech-stack.md` + `15-phase-14-pr-and-merge.md` → platform pipeline |
| `dev:review` | 15 | `00-principles.md` + `18-output-and-universal-rules.md` + `02-phase-01-context-load.md` + `16-phase-15-review-cycle.md` |
| `dev:docs` | 12 | `00-principles.md` + `18-output-and-universal-rules.md` + `13-phase-12-docs.md` |
| `dev:code-review` | 13 | `00-principles.md` + `18-output-and-universal-rules.md` + `14-phase-13-code-review.md` — the diff is the whole subject |
| `dev:prod` | 16 | `00-principles.md` + `18-output-and-universal-rules.md` + `17-phase-16-prod-promotion.md` — plus the release runbook, per Workspace Resolution above |
| `dev:rollback` | 16 ↺ | `00-principles.md` + `18-output-and-universal-rules.md` + `02-phase-01-context-load.md` + `17-phase-16-prod-promotion.md` — plus classification and dual-branch sync |
| `dev:audit` | — | `00-principles.md` + `18-output-and-universal-rules.md` — mechanical phase compliance verification against evidence |
| `dev:launch` | — | **nothing** — it is a tool, not a phase; it detects the project and launches it |
| `dev:launch-kill` | — | **nothing** — a tool; it reads `dev:launch`'s discovery, not this pipeline |
| `dev:shots` | — | **nothing** — a tool; it reads `dev:launch`'s discovery and that skill's Phase 3, not this pipeline's |
| `dev:board` | — | **Universal Rules only** (`18-output-and-universal-rules.md`) — it skips Right-Size (ceremony on a board) but consumes *never guess ticket content* |
| `dev:comment-budget` | — | **Guiding Principles + Universal Rules only** (`00-principles.md` + `18-output-and-universal-rules.md`) — a tool, so it skips Right-Size, but it APPLIES Short Documentation and cannot improvise a rule it never read |
| `dev:arch` | — | **Guiding Principles + Universal Rules only** (`00-principles.md` + `18-output-and-universal-rules.md`) — a tool, so it skips Right-Size; it consumes Simplicity First, which is what lets it REFUSE a diagram the target does not need |
| `dev:findings` · `dev:ideation` | — | **Guiding Principles + Universal Rules + Right-Size** (`00-principles.md` + `18-output-and-universal-rules.md`) — the family's largest fan-out reads the rule that governs fan-outs. Not Phase 0: it delegates filing to the `dev:create-*` doors, which load it themselves |

**A tool-kind door loads only what it consumes.** The always-list is the floor for *phases*, which
are sized by tier; a tool runs no phase, so Right-Size has nothing to size and loading it is the
ceremony GUIDE principle 4 refuses. That is why every tool row above reads `nothing` — except
`dev:comment-budget`, `dev:findings`, `dev:ideation` and `dev:arch`. `comment-budget` **applies a rule**, and a rule it has not read is a
rule it will improvise; `findings` **fans out wider than any phase does**, so the one section a tool
would normally skip — Right-Size — is the one it most needs; `arch` **refuses targets**, and
Simplicity First is the rule it refuses them with. Read what you consume; name it in the row, and let the
row disagree with the default when the door earns it.

**The `dev:create-*` doors take no tier**, which is the one exception to the always-load list above.
A tier answers *how much process does building this deserve* — filing builds nothing, and Phase 0 is
one turn by construction. Their header line ends at the repo.

`dev:launch` is a family member of a different **kind**: the others are *phases*, it is a *tool*. It
maps to no phase number and loads none of this preamble — it builds and launches the app. Phases 4
and 11 call it for mobile targets (`/dev:launch ios sim`, `/dev:launch android emulator`), and it is
equally useful on its own for a throwaway prototype.

It belongs in this repo because it is the pipeline's only **personal-skill** dependency: everything
else the pipeline calls (`superpowers:*`, `code-review` as `dev:code-review`'s engine, `security-review`, `frontend-design`,
`supabase`, `feature-dev:*`) is a plugin that installs anywhere. `dev:launch` is the one that would
simply be missing after a clone, taking mobile verification down with it.

**`dev:arch` is the family's one THIRD-PARTY dependency, and a different category again.** It renders
through [Archify](https://github.com/tt-a1i/archify) — an external MIT package, not an Anthropic
plugin and not a personal skill — and it does not degrade: without Archify the door stops rather than
falling back to an unvalidated picture, because the validator is the entire reason to prefer it over
a hand-drawn SVG. That coupling is deliberate and it is the skill's largest risk; it is written down
in that skill's *Known limits* rather than left for a reader to discover.

`dev:docs` reads `PROJECT_MAP.md` as its *subject*, not as context load — checking whether it is
current is the job, not the preparation.

Then execute only the phase(s) your own skill file names.

---

## Response header

The pipeline's full `Output Header Format` (Source / Type / Branch / Stack / Platform pipeline /
Scope / Context) is for a `dev` run, where every field is populated. A sibling enters mid-stream
with most of them empty, so it opens with **one line** instead:

```
Dev · <sibling> — Phase <N> | <repo> | <branch or diff> | <tier>
```

State any assumption you had to make in that same line or immediately under it. Never pad it with
fields you inferred rather than resolved.

---

## The family

| Skill | Phase | Input it needs | Kind |
|---|---|---|---|
| `dev:create-bug` | 0 | a description of what is broken | **filing** |
| `dev:create-issue` | 0 | a description of the work | **filing** |
| `dev:create-epic` | 0 | a description spanning several tasks | **filing** |
| `dev` | Entry 1–2 → 1–16 | issue ref or a description | full run |
| `dev:verify` | 11 | a branch | stage |
| `dev:docs` | 12 | a diff | gate |
| `dev:code-review` | 13 | a branch | gate |
| `dev:pre-prod` | 14 | a branch | stage |
| `dev:review` | 15 | a PR number | **loop** ↺ |
| `dev:prod` | 16 | pre-prod + prod branches | stage |
| `dev:rollback` | 16 ↺ | a broken commit or release | recovery |
| `dev:audit` | — | a PR number or branch diff | audit / gate |
| `dev:launch` | — | a project to launch | **tool** |
| `dev:launch-kill` | — | a project to stop | **tool** |
| `dev:shots` | — | a running app | **tool** |
| `dev:board` | — | the repo's tracker | **tool** |
| `dev:comment-budget` | — | a repo or a path | **tool** |
| `dev:arch` | — | a system to draw | **tool** |
| `dev:findings` | — | an existing app | **tool** → feeds Phase 0 |
| `dev:roadmap` | — | the repo's own evidence | **tool** → feeds Phase 0 |
| `dev:insights` | — | a question | **tool** → maintains `PROJECT_MAP.md` |
| `dev:ideation` | — | an existing app | **tool** → feeds Phase 0 |

**Why these phases and not more:** Phases 1–8 pass *reasoning* between each other, and reasoning
lives only in the conversation that produced it — there is no artifact to hand a fresh session.
From Phase 11 on, every phase takes a durable artifact (branch, diff, PR number), which is exactly
what makes it independently invocable. Phase 0 qualifies from the opposite side of that seam: it
runs before any reasoning exists, takes only a description, and produces an issue number. Phase 13 is deliberately absent: it is 20 lines that mostly
say "run Phase 13", so run `dev:code-review`.

---

## Rules for every sibling

- **Never re-run the phases before yours.** If the branch's earlier phases were skipped, say so
  and let the developer decide — do not silently backfill a plan or a spec.
- **State what you assumed.** Which branch, which base, which tier — one line, before acting.
- **A sibling never promotes to production autonomously.** `dev:prod` asks. Always.

### Never end silently

**Applies to every entry point, including a full `dev` run that stops early.** Entering at Phase 11
means the developer is standing in the MIDDLE of a pipeline when your phase finishes, not at the end
of one. So close every invocation by naming **the next phase, what it would do, and where it ends**
— then ask:

> "Phase 12 clean. Next is Phase 13 (`dev:code-review`) on the same diff, then Phase 14 opens the PR
> and merges to `staging`. Continue?"

Stopping flat is the failure this closes: it makes the developer remember both that there IS more
and what it is called, which is precisely the work the family exists to absorb. Say it even when
nothing follows — `dev:prod` ends by offering the tracker write-back, not with silence.

This is an **ask**, not a chain:

- **Chaining — proceeding WITHOUT asking — is allowed only between adjacent READ-ONLY gates, and
  only one hop.** `dev:verify` → `dev:docs` is the one wired pair: same diff, adjacent phases
  (11 → 12), both read-only, and their outputs are the two halves of one PR body. Everywhere else,
  you ask. `dev:docs` chains into `dev:code-review`, and **nothing ever chains into a merge or a
  promotion** — those are decisions, not steps.
