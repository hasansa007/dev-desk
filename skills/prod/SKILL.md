---
name: prod
description: >
  Promote already-merged, already-verified work from the pre-prod branch to PRODUCTION — verify in
  pre prod, apply migrations to prod BEFORE the merge, read what is actually in the promotion, then
  ask for the release decision and merge.
  Trigger when the user says "promote to prod", "release to production", "ship it to prod",
  "staging to main", "push this live", or asks to promote a pre-prod branch.
  NOT for merging a feature branch — that is `dev:pre-prod`.
allowed-tools: [gh, git]
---

# Dev — Prod Promotion

Standalone entry into **Phase 16 — Prod Promotion** of the dev pipeline.

## Input

The pre-prod branch and the prod branch, both resolved by `shared/entry.md`. **State them
explicitly before acting.** If they resolve to the same branch, the repo has a single-stage
model — say so and stop; Phase 14's merge already reached production.

## Run

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it.
2. Read `~/.claude/skills/dev/shared/pipeline/17-phase-16-prod-promotion.md` → execute **Phase 16 — Prod Promotion**.
3. Present, then ask. **Never promote autonomously.**

## Why this is a second gate, not a formality

The evidence that cleared Phase 11 was gathered against **pre prod**. The two environments differ
precisely where the risk lives — real keys, real payment provider, real storage backend, real data
volume. A change can be green in pre prod and wrong in production for reasons no local suite can
reach.

And the two decisions are days apart: Phase 11's prod decision approved the **work**; this one
approves the **release**.

## The sequence and its guards

**Phase 16, steps 1–6, unchanged** — verify in pre prod, check the release's secrets before anything
irreversible, migrations before the merge, never merge into a running build, read
`git log <prod>..<pre-prod>`, then ask. They are written there and only there. This door restates none of them, because it is loaded *alongside* the pipeline, not instead
of it — and a guard copied here is a guard that will disagree with Phase 16 the first time either is
edited.

## Next — ask, never stop flat

Phase 16 is the last phase, which makes this the easiest place to stop flat — and the worst, because
the tracker is now the only thing that still says the work is unfinished. End by offering the
write-back (`entry.md` → *Never end silently*):

> "Promoted — `<sha>` is live. Nothing follows in the pipeline, but the issues this closes are still
> open: `Closes #N` never fires here (feature PRs target the pre-prod branch, and GitHub honours the
> keyword only on the default branch). Want me to close #N and #M with a comment linking the PRs?"
