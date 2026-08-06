---
name: pre-prod
description: >
  Take finished work to PRE PROD — push, open the PR, run the pre-merge gates (docs, code review),
  then merge to the pre-prod branch (`staging`, typically). Ends at pre prod, never at
  production.
  Trigger when the user says "open a PR for this", "PR this branch", "merge to staging", "take this
  to staging", "ship this to pre prod", or when work is finished and needs to reach the shared
  environment. NOT for promoting staging to production — that is `dev:prod`.
allowed-tools: [gh, git]
---

# Dev — Pre Prod

Standalone entry into **Phase 14 — PR Creation → Review → Merge → Pre Prod**.

## Input

A branch with the work committed. The base is the **pre-prod branch** resolved by
`shared/entry.md` — never assume it.

## Run

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it. **State the resolved base branch
   before doing anything** — getting this wrong means a PR that never deploys.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 14** in full, including the
   `Phase 14 Additions` from `dev/SKILL.md` when the source is a GitHub issue (`Closes #N`, labels).

## The sequence and its guards

**push → PR → review → merge → pre prod.** The sequence, the pre-merge gates, the runbook override,
the required PR sections and the commit-hygiene rules are all written in **Phase 14** and Universal
Rules — and only there. This door is loaded alongside the pipeline, not instead of it; a gate copied
here is a gate that will disagree with Phase 14 the first time either is edited.

The one thing worth saying twice, because getting it wrong is silent: **this ends at PRE PROD.**
Never report the work as "shipped" or "live".

## Next — ask, never stop flat

End by naming what remains and asking (`entry.md` → *Never end silently*):

> "Merged to `<pre-prod branch>` — this is pre prod, not production. Phase 16 (`dev:prod`) promotes
> it, and it needs its own decision plus any pending migrations applied first. Promote now, or let
> it sit in pre prod?"

`dev:review` (Phase 15) if reviewers request changes — it loops back into these gates, not forward.
