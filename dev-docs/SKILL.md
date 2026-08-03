---
name: dev-docs
description: >
  Check that docs, ADRs and PROJECT_MAP are current for a branch's diff BEFORE it merges — prices
  and limits, decisions with their rejected alternatives, env vars, migrations, new modules, and
  work deliberately deferred. Produces the PR body's `## DOCS` section.
  Trigger when the user says "are the docs updated", "check the ADRs", "docs gate", "did we write
  this decision down", "is PROJECT_MAP current", or before merging anything that changed a number
  or a decision.
allowed-tools: [gh, git]
---

# Dev — Docs & Decisions Gate

Standalone entry into **Phase 12 — Docs & Decisions Gate** of the dev pipeline.

## Input

A branch, or any diff: `git diff <BASE_BRANCH>...HEAD`.

## Run

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 12** against the diff.
3. Output the `## DOCS` section verbatim, ready to paste into the PR body.

## Why this exists as its own entry point

This gate has **failed in execution before.** A funnel branch merged with green suites and a full
verification table but no ADR and a stale `PROJECT_MAP` claim — caught only because the developer
thought to ask. Making it invocable means the question "are the docs actually current?" can be
asked directly, at any time, instead of depending on remembering it mid-run.

The rationalization it counters: *"suites green + evidence table done = ready."* It is not. The
ADR is part of the diff.

## The check

| If the diff contains… | Then update… |
|---|---|
| a changed price, limit, cap or plan | the monetization/pricing doc — every number AND why it is that number |
| a decision with a rejected alternative | a new ADR — including the alternative and why it lost |
| a new/changed env var, migration or runbook step | the release/ops doc |
| a new module, flow or entry point | `PROJECT_MAP.md` (`TECH_STACK` / `SYSTEM_FLOW`) |
| work deliberately deferred | `ORPHANS & PENDING` — not a memory of it |

## Output

Either the list of ADRs and docs updated in this branch, or the explicit line:

> none needed — checked: no price/limit, no decision-with-alternative, no env/migration,
> no new module, no deferred work, no doc made stale

A PR without a `## DOCS` section is not ready to merge.

## Guards

- **Write the alternatives you REJECTED, with their arithmetic.** A log listing only what was
  chosen cannot tell a future reader why the obvious other path is wrong — so they will re-propose
  it, and you will re-argue it from memory.
- **State what is decided but NOT built.** A doc describing behaviour that does not exist is worse
  than silence — mark it pending, with what it needs.
- **A change implementing PART of a decision must record the remainder.** Go back to that ADR and
  write which half is live and which is still intent.
- Docs written after the merge get written from memory, and memory keeps the conclusion while
  losing the reason. **Run this before the merge, never after.**
