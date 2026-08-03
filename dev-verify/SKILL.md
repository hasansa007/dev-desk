---
name: dev-verify
description: >
  Run the agent-executed verification checklist against a branch that already exists — build the
  evidence table, drive the real app (Chrome DevTools MCP / simulator / adb), attach screenshots
  and console+network output per row, then tear down what was spawned.
  Trigger when the user says "verify this branch", "does this actually work", "test this branch",
  "run the checklist", "prove it works", or asks for evidence that a finished change behaves.
  Does NOT plan or implement — the code must already be written.
allowed-tools: [gh, git]
---

# Dev — Verify

Standalone entry into **Phase 9 — Verification Gate** of the dev pipeline.

## Input

A branch that already has the work committed. Nothing else — this skill does not need the plan,
the spec, or the conversation that produced the code.

If the working tree is dirty, say so and ask whether to verify the committed state or the
working state. They are different claims.

## Run

1. Read `~/Developer/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/dev-skill/shared/pipeline.md` → execute **Phase 9 — Verification Gate**
   in full, including the platform additions from the matching `pipeline-<platform>.md`.
3. Present the evidence table. Hand back only the rows you genuinely cannot reach.

## What this skill is for

The pipeline's Phase 9 is 99 lines and it is the fattest phase for a reason: **the agent executes
the checklist, the developer is not the test runner.** Every row gets real evidence — a screenshot,
a console excerpt, a network status — never a narrative claim.

Carry the three passes over from the pipeline, none of them optional:

- **Pass 1** — one row per acceptance criterion or reported symptom
- **Pass 2** — diff-scoped regression rows (`git diff <BASE>...HEAD --name-only`)
- **Pass 2b** — shared-surface rows: **enumerate the consumers, don't reason about them**
- **Pass 3** — make each row runnable: the exact mechanism, not the intent

## Guards

- **Tear down what you started.** The DevTools MCP Chrome, emulators, docker fixtures, background
  shells — killed in the same turn the rows finish, matched by profile path and never by app name.
  Report the teardown as one line of evidence. Never touch the developer's own browser or their
  dev server.
- **No claims without fresh output.** Apply `verification-before-completion`. State skipped tests
  explicitly rather than reporting a bare pass count.
- **Include a falsification row** — the check that would prove the change WRONG if it failed. A
  checklist that can only confirm you is not a test.
- **The checklist must land where the tester looks.** Chat-only is a failure of this phase: carry
  it into the PR body's `## HOW TO TEST`, or `gh pr comment` it if the PR is already open.

## Next

Verification passing is not permission to merge. `dev-docs` (Phase 9.4) and `/code-review`
(Phase 9.5) are still gates, and `dev-pre-prod` (Phase 10) is what actually merges.
