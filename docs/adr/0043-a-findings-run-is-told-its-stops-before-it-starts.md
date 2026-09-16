# 0043 — A findings run is told its stops before it starts, and refuses past its agent limit

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Amends `shared/pipeline/00-principles.md` → Right-Size (*"never open a fan-out on the developer's behalf"*)
for `dev:findings` and `dev:ideation`.

## Context

The developer ran findings on CallApp from Dev Desk three times on 2026-09-16. Each run stopped at
Phase 4's *"Go, or narrow it?"* and waited. The developer, 2026-09-16: *"let the agent decide the proper
decision and run, think about run in background — it will be stuck"*. A background run has no terminal to
answer in; the app does show **Answer…**, but only to someone looking. The same holds for Phase 8's
per-finding walkthrough and Phase 9's filing question.

The Antigravity run that day also treated a deleted report's findings, still in git history, as already
verified, and batched four findings per checker.

## Decision

- **Three stops, each chosen in the run sheet before the run starts:** planning agents (Decide for me /
  Alert me), walkthrough and filing (Decide for me / Alert me / Skip). Defaults: Decide, Skip, Skip. Remembered
  per project and door. Passed as `--plan`, `--walkthrough`, `--file`.
- **`--max-agents`** (Settings → Execution, default 40). Over the limit the run starts nothing and ends
  with a `Refused:` line, which Dev Desk shows as a failed run (developer: *"show error message"*).
- **Without the arguments a door asks at every stop, as before**, so a terminal run outside Dev Desk is
  unchanged.
- **Every run is from scratch**; earlier reports are only dedupe input.
- Flows are split per thing a user does, not per screen.

## Rejected

```
rejected: always decide, no choice — the walkthrough is how the developer builds a model of the system,
          and some runs are watched live for exactly that
rejected: narrow silently to the limit — a run that quietly surveyed half the app reads as a clean half
rejected: a per-project "never ask" setting — hides the choice in Settings instead of beside Run
```
