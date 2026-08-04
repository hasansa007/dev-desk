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

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 0 — Filing** in full.
3. Fill the template below. Default type label: whatever this repo uses for epics — read
   `gh label list`, do not assume one exists.

## This files the PARENT ONLY — that is the point

The slices are cut at **Phase 5**, on the first `/dev #N` against this epic, because that is the
first moment they are *informed*: context load, stack discovery and investigation have all run by
then. Cut here, they would be imagined from a description — and a wrong slice boundary is expensive,
because each slice becomes a branch, a PR and a promotion.

So this skill does not decompose, and it does not ask you to. It captures the boundary; Phase 5
finds the seams inside it.

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

- **Slices never go in the body**, not as prose and not as `- [ ]` lines — even when they seem
  obvious now. Phase 5's decomposition step owns why, and the `sub_issues` mechanics with it.
- **If it turns out to be one task, file one task.** Say so and use `dev:create-issue`. An epic with
  a single child is overhead with a label on it.

## Next

Phase 0 hands off as usual — but for an epic the handoff is specifically:

> "Filed epic #174. Running `/dev #174` next will investigate it and propose the slices at Phase 5
> before filing any children. Start now, or leave it?"
