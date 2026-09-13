---
name: verify
description: >
  Run the agent-executed verification checklist against a branch that already exists — build the
  evidence table, drive the real app (Chrome DevTools MCP / simulator / adb), attach screenshots
  and console+network output per row, then tear down what was spawned. When every row passes it
  chains automatically into the docs/ADR gate (dev:docs) on the same diff.
  Trigger when the user says "verify this branch", "does this actually work", "test this branch",
  "run the checklist", "prove it works", or asks for evidence that a finished change behaves.
  Does NOT plan or implement — the code must already be written.
allowed-tools: [gh, git]
---

# Dev — Verify

Standalone entry into **Phase 11 — Verification Gate** of the dev pipeline.

## Input

A branch that already has the work committed. Nothing else — this skill does not need the plan,
the spec, or the conversation that produced the code.

If the working tree is dirty, say so and ask whether to verify the committed state or the
working state. They are different claims.

## Run

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it.
2. Read `~/.claude/skills/dev/shared/pipeline/12-phase-11-verification.md` → execute **Phase 11 — Verification Gate**
   in full, including the platform additions from the matching `pipeline-<platform>.md`.
3. Present the evidence table. Hand back only the rows you genuinely cannot reach.

## What this skill is for

The pipeline's Phase 11 is 99 lines and it is the fattest phase for a reason: **the agent executes
the checklist, the developer is not the test runner.** Every row gets real evidence — a screenshot,
a console excerpt, a network status — never a narrative claim.

Its four passes, its teardown rule, its falsification row and its where-the-checklist-lands rule are
all written in Phase 11 — **none of them optional, and none of them repeated here.** This door is
loaded alongside the pipeline, not instead of it, and a guard copied here is a guard that will
disagree with Phase 11 the first time either is edited.

## Then chain into `dev:docs` — automatically

**When every row is ✅, continue straight into `dev:docs` (Phase 12) against the same diff.** Do not
ask first; announce it and run it. The two produce the two halves of the same PR body
(`## HOW TO TEST` and `## DOCS`), they are adjacent phases, and `dev:docs` is read-only — so
stopping between them buys nothing and costs the gate.

This closes the failure mode Phase 12 was written for: a branch with **green suites and a full
verification table** merged with its ADR unwritten, caught only because the developer thought to
ask. Green evidence is the moment that feels like done — which is exactly when the docs gate gets
skipped.

```
Verification clean — running dev:docs (Phase 12) on the same diff.
```

**Do NOT chain when:**

- **any row is ❌** — fix first, re-run the affected rows, then chain. A docs gate on a branch that
  does not work is measuring the wrong thing
- **rows were handed back as unreachable and they carry the real risk** — say so and let the
  developer decide whether to proceed
- the developer asked for verification *only*

Chaining stops there. `dev:code-review` (Phase 13) and `dev:pre-prod` (Phase 14) are separate
decisions — Phase 14 merges, and nothing auto-runs a merge.

## Next — ask, never stop flat

Verification passing is not permission to merge. After the `dev:docs` chain, end by naming the rest
and asking (`entry.md` → *Never end silently*):

> "Rows green, docs gate clean. Next is Phase 13 (`dev:code-review`) on the same diff, then
> `dev:pre-prod` (Phase 14) opens the PR and merges to `<pre-prod branch>`. Continue?"

If any row was ❌ or handed back as unreachable, say that FIRST — the question is then whether to
proceed at all, not which phase comes next.
