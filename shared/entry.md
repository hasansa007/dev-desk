# Dev Family — Shared Entry Contract

Read by `dev` and by every `dev-*` sibling **before anything else**. One source of truth for
workspace resolution and for which pipeline sections always load.

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
(`shared/prod-secrets.md`), which moves to Phase 14 and runs before that merge. It is bound to the
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
   anything lands.

> **2026-08-05 → 06 — read-boundary written, write-boundary missing.** A boundary rule was added to
> `dev:issues` after it rendered another repo's board — read-only, and the user still had to ask
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

## What to load from `shared/pipeline.md`

**Always, for every entry point** — these are cheap and they govern how you work:

| Section | Why |
|---|---|
| Guiding Principles | Simplicity First, Stop on Ambiguity, Surgical Editing |
| Right-Size the Process | pick Light / Standard / Deep and SAY which |
| Universal Rules | commit hygiene, no AI attribution, no worktrees in this repo |

**Conditionally** — a sibling loads these only when its own phase actually consumes them.
Right-Size applies to the preamble too: loading discovery for a read-only gate is the ceremony
this pipeline exists to refuse.

| Section | Load it when | So: |
|---|---|---|
| **Phase 1 — Context Load** | your phase reads or changes code, and needs to know the system | `dev:verify`, `dev:review` |
| **Phase 2 — Tech Stack & Discovery** | **your phase has a platform overlay.** `pipeline-<platform>.md` defines additions to Phases 10, 11 and 14 ONLY — no other phase has one, so no other phase needs the stack detected | `dev:verify` (11), `dev:pre-prod` (14) |

| Sibling | Phase | Loads |
|---|---|---|
| `dev` | 1–16 | everything except Phase 0 — the item already exists by the time it runs |
| `dev:create-bug` | 0 | always **minus Right-Size** + Phase 0 |
| `dev:create-issue` | 0 | always **minus Right-Size** + Phase 0 |
| `dev:create-epic` | 0 | always **minus Right-Size** + Phase 0 |
| `dev:verify` | 11 | always + Phase 1 + Phase 2 → platform pipeline |
| `dev:pre-prod` | 14 | always + Phase 2 → platform pipeline |
| `dev:review` | 15 | always + Phase 1 |
| `dev:docs` | 12 | always only |
| `dev:prod` | 16 | always only — plus the release runbook, per Workspace Resolution above |
| `dev:launch` | — | **nothing** — it is a tool, not a phase; it detects the project and launches it |
| `dev:trim` | — | **Guiding Principles + Universal Rules only** — it applies Short Documentation, so it must read it |

**The `dev:create-*` doors take no tier**, which is the one exception to the always-load list above.
A tier answers *how much process does building this deserve* — filing builds nothing, and Phase 0 is
one turn by construction. Their header line ends at the repo.

`dev:launch` is a family member of a different **kind**: the others are *phases*, it is a *tool*. It
maps to no phase number and loads none of this preamble — it builds and launches the app. Phases 4
and 11 call it for mobile targets (`/dev:launch ios sim`, `/dev:launch android emulator`), and it is
equally useful on its own for a throwaway prototype.

It belongs in this repo because it is the pipeline's only **personal-skill** dependency: everything
else the pipeline calls (`superpowers:*`, `/code-review`, `security-review`, `frontend-design`,
`supabase`, `feature-dev:*`) is a plugin that installs anywhere. `dev:launch` is the one that would
simply be missing after a clone, taking mobile verification down with it.

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
| `dev:pre-prod` | 14 | a branch | stage |
| `dev:review` | 15 | a PR number | **loop** ↺ |
| `dev:prod` | 16 | pre-prod + prod branches | stage |
| `dev:launch` | — | a project to launch | **tool** |
| `dev:trim` | — | a repo or a path | **tool** |

**Why these phases and not more:** Phases 1–8 pass *reasoning* between each other, and reasoning
lives only in the conversation that produced it — there is no artifact to hand a fresh session.
From Phase 11 on, every phase takes a durable artifact (branch, diff, PR number), which is exactly
what makes it independently invocable. Phase 0 qualifies from the opposite side of that seam: it
runs before any reasoning exists, takes only a description, and produces an issue number. Phase 13 is deliberately absent: it is 20 lines that mostly
say "run `/code-review`", so run `/code-review`.

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

> "Phase 12 clean. Next is Phase 13 (`/code-review`) on the same diff, then Phase 14 opens the PR
> and merges to `staging`. Continue?"

Stopping flat is the failure this closes: it makes the developer remember both that there IS more
and what it is called, which is precisely the work the family exists to absorb. Say it even when
nothing follows — `dev:prod` ends by offering the tracker write-back, not with silence.

This is an **ask**, not a chain:

- **Chaining — proceeding WITHOUT asking — is allowed only between adjacent READ-ONLY gates, and
  only one hop.** `dev:verify` → `dev:docs` is the one wired pair: same diff, adjacent phases
  (11 → 12), both read-only, and their outputs are the two halves of one PR body. Everywhere else,
  you ask. Nothing chains into `/code-review`, and **nothing ever chains into a merge or a
  promotion** — those are decisions, not steps.
