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

  studyhub-deploy: pre prod = `staging`, prod = `main`. A feature PR based on `main`
  never deploys, and merging to `main` DEPLOYS PROD. Confirm both before acting.
```

If the two resolve to the same branch, the repo has a **single-stage model**: Phase 14's merge
already reaches production. Say so explicitly, and skip Phase 16.

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
| `dev` | 1–16 | everything — it runs every phase |
| `dev:verify` | 11 | always + Phase 1 + Phase 2 → platform pipeline |
| `dev:pre-prod` | 14 | always + Phase 2 → platform pipeline |
| `dev:review` | 15 | always + Phase 1 |
| `dev:docs` | 12 | always only |
| `dev:prod` | 16 | always only — plus the release runbook, per Workspace Resolution above |
| `dev:run` | — | **nothing** — it is a tool, not a phase; it detects the project and launches it |

`dev:run` is a family member of a different **kind**: the others are *phases*, it is a *tool*. It
maps to no phase number and loads none of this preamble — it builds and launches the app. Phases 4
and 11 call it for mobile targets (`/dev:run ios sim`, `/dev:run android emulator`), and it is
equally useful on its own for a throwaway prototype.

It belongs in this repo because it is the pipeline's only **personal-skill** dependency: everything
else the pipeline calls (`superpowers:*`, `/code-review`, `security-review`, `frontend-design`,
`supabase`, `feature-dev:*`) is a plugin that installs anywhere. `dev:run` is the one that would
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
| `dev` | Entry 1–2 → 1–16 | issue ref or a description | full run |
| `dev:verify` | 11 | a branch | stage |
| `dev:docs` | 12 | a diff | gate |
| `dev:pre-prod` | 14 | a branch | stage |
| `dev:review` | 15 | a PR number | **loop** ↺ |
| `dev:prod` | 16 | pre-prod + prod branches | stage |
| `dev:run` | — | a project to launch | **tool** |

**Why these five phases and not more:** Phases 1–8 pass *reasoning* between each other, and reasoning
lives only in the conversation that produced it — there is no artifact to hand a fresh session.
From Phase 11 on, every phase takes a durable artifact (branch, diff, PR number), which is exactly
what makes it independently invocable. Phase 13 is deliberately absent: it is 20 lines that mostly
say "run `/code-review`", so run `/code-review`.

---

## Rules for every sibling

- **Never re-run the phases before yours.** If the branch's earlier phases were skipped, say so
  and let the developer decide — do not silently backfill a plan or a spec.
- **State what you assumed.** Which branch, which base, which tier — one line, before acting.
- **A sibling never promotes to production autonomously.** `dev:prod` asks. Always.
