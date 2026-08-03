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

## Always load from `shared/pipeline.md`

Every entry point in this family loads these, whatever phase it then runs:

| Section | Why it is never optional |
|---|---|
| Guiding Principles | Simplicity First, Stop on Ambiguity, Surgical Editing |
| Right-Size the Process | pick Light / Standard / Deep and SAY which |
| Phase 0 — Context Load | `PROJECT_MAP.md`, `ARCHITECTURE.md`, existing spec |
| Phase 2 — Tech Stack & Project Discovery | stack detect → the matching `pipeline-<platform>.md` |
| Universal Rules | commit hygiene, no AI attribution, no worktrees in this repo |
| Output Header Format | the response header |

Then execute only the phase(s) your own skill file names.

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
