---
name: create-issue
description: >
  File a FEATURE or TASK into the repo's GitHub tracker — read the tracker's house style, draft the
  whole issue, ask only what could not be inferred, then create it with real labels.
  Trigger when the user says "file an issue", "create an issue", "open a ticket", "capture this",
  "add this to the tracker", or describes work they want recorded rather than started now.
  Use `dev:create-bug` for something broken, `dev:create-epic` for work spanning several tasks.
allowed-tools: [gh, git]
---

# Dev — File an Issue

Standalone entry into **Phase 0 — Filing**. Produces an issue number, nothing else.

## Input

A rough description of the work. The default door when it is neither plainly a bug nor plainly
epic-sized.

## Run

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it.
2. Read `~/.claude/skills/dev/shared/pipeline/01-phase-00-filing.md` → execute **Phase 0 — Filing** in full.
3. Fill the template below. Default type label: whatever this repo uses for features
   (`enhancement` / `feature` / `task`) — read `gh label list`, do not assume which.
4. **Propose `impact:` and `complexity:`** from what the work is worth and how big it looks, marked
   as assumptions for the developer to correct (`docs/guide/WORKFLOW.md` → *Rating an issue*). Offer
   to create either label the repo lacks; never create one silently.

## Template

```
## What
<the outcome, stated as what the user can do afterwards — not as an implementation>

## Why
<the reason it is worth doing; the trigger or the cost of not doing it>

## Done when
- <observable condition>
- <observable condition>
```

**`## What` describes the outcome, not the change.** *"A learner returns to a course and lands where
they left off"* survives a redesign; *"add a scrollPosition field to the course store"* is a plan,
and it silently decides Phase 5's answer before Phase 5 has run.

**`## Done when` is the seed of Phase 11's Pass 1** — one verification row per line. A condition you
cannot imagine executing is one to rewrite now, while it is one line, rather than at Phase 11 where
it becomes an unrunnable row.

## Guards specific to features

- **State it once.** No preamble, no "currently…", no restating `## What` inside `## Why`. Two
  sentences that say one thing are one sentence. A `## Done when` row you cannot execute is prose,
  not a condition.
- **Escalate rather than cram.** If drafting reveals this is several tasks with different surfaces,
  say so and offer `dev:create-epic` instead. One issue that is secretly three is the shape that
  later gets half-closed — and Phase 0's *one item per invocation* rule exists for exactly this.
- **Do not design it.** No file paths, no component names, no schema. The issue states the outcome;
  Phase 5 discusses the shape and Phase 6 weighs alternatives. A design smuggled into the issue body
  arrives at Phase 5 already looking decided.
