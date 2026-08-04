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

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 16 — Prod Promotion**.
3. Present, then ask. **Never promote autonomously.**

## Why this is a second gate, not a formality

The evidence that cleared Phase 11 was gathered against **pre prod**. The two environments differ
precisely where the risk lives — real keys, real payment provider, real storage backend, real data
volume. A change can be green in pre prod and wrong in production for reasons no local suite can
reach.

And the two decisions are days apart: Phase 11's prod decision approved the **work**; this one
approves the **release**.

## The sequence

1. **Verify in pre prod first.** Run the rows only a deployed environment can answer — the ones
   Phase 11 handed over as unreachable (real OAuth, real payments, real storage). A green local
   suite is not pre-prod verification.
2. **Migrations reach prod BEFORE the promotion merge** — never after, never during. The merge
   releases code that expects the new schema; a schema arriving second is an outage. Rehearse on
   pre prod, dry-run against prod, then apply, then merge. Use the `supabase` skill for the
   mechanics.
3. **Never merge while a build is running.** Two releases racing produce a deployment you cannot
   attribute and a rollback that restores the wrong thing.
4. **Read what is actually in the promotion:**
   ```bash
   git log <prod>..<pre-prod> --oneline
   ```
   It is a diff of already-reviewed commits, so it needs no second code review — but anything you
   did not expect stops the promotion until you know why it is there.
5. **Ask.** Present three things — what is in the promotion, what was verified in pre prod, which
   migrations are already applied — then wait for the developer's word.

## studyhub-deploy

Feature PRs target `staging`; the **`staging → main` merge AUTO-DEPLOYS PROD**, so the merge IS
the gate — there is no separate deploy step to catch a mistake afterwards. `staging` drifts behind
`main`; catch up with `git push origin origin/main:staging`. Full flow in
`docs/deploy-and-staging.md`.

## Guards

- **Never autonomously.** This skill always ends in a question, whatever the automation level.
- **Do not merge while a build runs.** Check first.
- **Migrations first, always.** If a migration is pending and unapplied, that is a stop, not a
  warning.
- If anything in `git log <prod>..<pre-prod>` is unexplained, stop and surface it.
