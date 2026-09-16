---
name: create-epic
description: >
  File an EPIC — work spanning several tasks — as one parent issue in the repo's GitHub tracker.
  Creates the parent only; the slices are cut later, at Phase 5, where investigation has actually
  happened.
  Trigger when the user says "file an epic", "create an epic", "this is a big one", "open a parent
  issue", or describes work that plainly spans several branches or sessions.
  Use `dev:create-issue` for a single task, `dev:create-bug` for something broken.
allowed-tools: [gh, git]
---

# Dev — File an Epic

Standalone entry into **Phase 0 — Filing**. Produces **one** issue number: the parent.

## Input

A rough description of work spanning several tasks.

## Run

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it.
2. Read `~/.claude/skills/dev/shared/pipeline/01-phase-00-filing.md` → execute **Phase 0 — Filing** in full.
3. Fill the template below. Default type label: whatever this repo uses for epics — read
   `gh label list`, do not assume one exists.
4. **Propose `impact:` and `complexity:` at epic level** — what the whole outcome is worth, and how
   big the whole thing is, not one slice's. Assumptions for the developer to correct
   (`docs/guide/WORKFLOW.md` → *Rating an issue*); a missing label is offered, never created silently.

## This files the PARENT ONLY — that is the point

The slices are cut at **Phase 5**, on the first `/dev #N` against this epic, because that is the
first moment they are *informed*: context load, stack discovery and investigation have all run by
then. Cut here, they would be imagined from a description — and a wrong slice boundary is expensive,
because each slice becomes a branch, a PR and a promotion.

So this skill does not decompose, and it does not ask you to. It captures the boundary; Phase 5
finds the seams inside it.

**One caller arrives informed: `dev:findings`** (ADR 0040). Its tickets were each investigated and
checked against the code by two refuting checkers before a group was drawn around them, so it hands
this skill the parent **and** the sub-issues, in group order. Filing them is not decomposing — the
seams were found at the findings run's Phases 4–5, which is the investigation this rule waits for.

## Template

```
## Goal
<the outcome the whole epic delivers, in one or two sentences>

## Why now
<the trigger, or the cost of not doing it>

## In scope
- <area>

## Out of scope
- <area — and why. This is the line Phase 5 cuts slices INSIDE>

## Done when
- <observable, epic-level — true only when every child is closed>
```

`## Out of scope` is the section that earns its place. An epic without a stated boundary grows one
task at a time, and nobody can point at the commit where it happened.

## Guards specific to epics

- **State it once.** No preamble, no "currently…", no restating `## Goal` inside `## Why now`. Two
  sentences that say one thing are one sentence, and a `## Done when` row you cannot execute is
  prose, not a condition.
- **Slices never go in the body**, not as prose and not as `- [ ]` lines — even when they seem
  obvious now. Phase 5's decomposition step owns why, and the `sub_issues` mechanics with it.
- **If it turns out to be one task, file one task.** Say so and use `dev:create-issue`. An epic with
  a single child is overhead with a label on it.

## Next

Phase 0 hands off as usual — but for an epic the handoff is specifically:

> "Filed epic #N. Running `/dev #N` next will investigate it and propose the slices at Phase 5
> before filing any children. Start now, or leave it?"
