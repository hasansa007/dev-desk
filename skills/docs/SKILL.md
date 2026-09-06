---
name: docs
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
| a decision with a rejected alternative | the PR body and commit message — including the alternative and why it lost |
| a new/changed env var, migration or runbook step | the release/ops doc |
| a new module, flow or entry point | `PROJECT_MAP.md` (`TECH_STACK` / `SYSTEM_FLOW`) |
| work deliberately deferred | `ORPHANS & PENDING` — not a memory of it |
| a moved/renamed/deleted file that any tracked diagram IR cites | the diagram — re-pin it, or delete it |

## Where ADRs live

**Undecided, and that is a real gap.** `skills/survey/SKILL.md` delegates here — *"`dev:docs` owns
ADRs, their numbering and location are its rules"* — and this skill has never answered it. A
convention in `docs/adr/` was written on 2026-09-06 and reverted the same day when `docs/` became
git-ignored: an ADR nobody can read from a clone is not a record.

Until it is decided, a decision with a rejected alternative goes in the **PR body** and the **commit
message**, and the losing options go with it. Be aware of what that costs: a squash merge rewrites
the commit, so the rationale then survives only on the forge — two of this repo's own decisions were
lost that way.

## The check that actually fails things

The table above asks whether the right document was **touched**. That is the easy half. The gate is
whether **every claim in the section you touched is still true** — a partial edit passes the
touched-test while leaving the doc lying.

For each doc the diff modifies, reread the **whole paragraph around the edit** — not your diff of
it — and ask of each sentence: *is this still true after this branch?* Fix or delete what is not.

Observed 2026-08-03: a branch added its ADR **and** updated its PROJECT_MAP
paragraph — green on every row of the table — while leaving three claims in that same paragraph
describing a rail the dialog no longer has. One mention had been fixed, three had not. **A partial
sweep is indistinguishable from a complete one from the outside**, so the pass criterion is the
reread, not the edit.

## Committed diagrams

`dev:arch` writes to `$SCRATCH` and nothing lands in the tree by default, so there is normally
nothing here to check.

**If a diagram is ever landed at a tracked path**, it comes with an `.architecture.json` beside it,
and this gate re-validates that IR against the branch's HEAD — not against the revision the IR names,
which always passes because the pinned commit still exists. Probe a copy:

```bash
probe=$(mktemp)   # bare mktemp — a ".json" suffix breaks the template on macOS
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));\
d['meta']['repository']['revision']=sys.argv[2];json.dump(d,open(sys.argv[3],'w'))" \
  "$ir" "$(git rev-parse HEAD)" "$probe"
node <archify>/bin/archify.mjs validate architecture "$probe" --repo-root . || echo "STALE: $ir"
```

That catches a moved or deleted file. It **cannot** catch a pure line shift — an insert above a cited
range moves it while every pin still resolves — so also intersect the IR's source paths with
`git diff --name-only "$(git merge-base origin/main HEAD)"` and re-read any that appear.

## Output

Either the list of ADRs and docs updated in this branch, or the explicit line:

> none needed — checked: no price/limit, no decision-with-alternative, no env/migration,
> no new module, no deferred work, no doc made stale

Either way, state the reread: *"reread §X and §Y in full — N claims corrected"*, or *"reread §X in
full — still accurate"*. An unstated reread did not happen.

If the repo tracks any diagram IR, state the result too — *"N/N diagrams re-validated at `<sha>`"* —
or say there are none.

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

## Next — ask, never stop flat

This gate is read-only and mid-pipeline, so finishing it is not finishing anything. End by naming
the rest and asking (`entry.md` → *Never end silently*):

> "Docs gate clean — ADR written, the PROJECT_MAP section reread. Next is Phase 13 (`/code-review`)
> on the same diff, then `dev:pre-prod` (Phase 14) opens the PR and merges to `<pre-prod branch>`.
> Continue?"
