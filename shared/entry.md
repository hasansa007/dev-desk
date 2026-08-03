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

If the two resolve to the same branch, the repo has a **single-stage model**: Phase 10's merge
already reaches production. Say so explicitly, and skip Phase 10.5.

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
| **Phase 0 — Context Load** | your phase reads or changes code, and needs to know the system | `dev-verify`, `dev-review` |
| **Phase 2 — Tech Stack & Discovery** | **your phase has a platform overlay.** `pipeline-<platform>.md` defines additions to Phases 8, 9 and 10 ONLY — no other phase has one, so no other phase needs the stack detected | `dev-verify` (9), `dev-pre-prod` (10) |

| Sibling | Phase | Loads |
|---|---|---|
| `dev` | 0–10.5 | everything — it runs every phase |
| `dev-verify` | 9 | always + Phase 0 + Phase 2 → platform pipeline |
| `dev-pre-prod` | 10 | always + Phase 2 → platform pipeline |
| `dev-review` | 10.2 | always + Phase 0 |
| `dev-docs` | 9.4 | always only |
| `dev-prod` | 10.5 | always only — plus the release runbook, per Workspace Resolution above |

`dev-docs` reads `PROJECT_MAP.md` as its *subject*, not as context load — checking whether it is
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
| `dev` | Entry 1–2 → 0–10.5 | issue ref or a description | full run |
| `dev-verify` | 9 | a branch | stage |
| `dev-docs` | 9.4 | a diff | gate |
| `dev-pre-prod` | 10 | a branch | stage |
| `dev-review` | 10.2 | a PR number | **loop** ↺ |
| `dev-prod` | 10.5 | pre-prod + prod branches | stage |

**Why these five and not more:** Phases 0–8 pass *reasoning* between each other, and reasoning
lives only in the conversation that produced it — there is no artifact to hand a fresh session.
From Phase 9 on, every phase takes a durable artifact (branch, diff, PR number), which is exactly
what makes it independently invocable. Phase 9.5 is deliberately absent: it is 20 lines that mostly
say "run `/code-review`", so run `/code-review`.

---

## Rules for every sibling

- **Never re-run the phases before yours.** If the branch's earlier phases were skipped, say so
  and let the developer decide — do not silently backfill a plan or a spec.
- **State what you assumed.** Which branch, which base, which tier — one line, before acting.
- **A sibling never promotes to production autonomously.** `dev-prod` asks. Always.
