---
name: create-bug
description: >
  File a BUG into the repo's GitHub tracker — read the tracker's house style, draft the whole
  report, ask only what could not be inferred, then create it with real labels.
  Trigger when the user says "file a bug", "open a bug", "log this bug", "create an issue for this
  bug", "report this", or describes something broken they want captured rather than fixed now.
  Does NOT investigate, reproduce or fix — that is `/dev #N` afterwards.
allowed-tools: [gh, git]
---

# Dev — File a Bug

Standalone entry into **Phase 0 — Filing**. Produces an issue number, nothing else.

## Input

A rough description of what is broken. One sentence is enough — drafting it is your job, not theirs.

## Run

1. Read `~/.claude/skills/dev/shared/entry.md` and apply it.
2. Read `~/.claude/skills/dev/shared/pipeline.md` → execute **Phase 0 — Filing** in full.
3. Fill the template below. Default type label: `bug`, if `gh label list` shows it exists.

## Template

```
## What happens
<the symptom, in the words a user would use>

## Steps
1. <exact mechanism — the menu path, the URL, the state>
2. …

## Expected
<what should happen instead>

## Scope
<where it bites: which pages, flows, platforms — and where it does NOT, if known>
```

`## Steps` carries the **mechanism, never the intent** — the same standard Phase 11's Pass 3 applies
to verification rows. *"Open a course with 40+ lessons, scroll to lesson 30, press back"* is a step;
*"navigate to a long course"* is a wish.

## Guards specific to bugs

- **State it once.** No preamble, no "currently…". `## What happens` is the symptom in a sentence
  or two, not a narrative — the mechanism lives in `## Steps` and belongs there only once.
- **A cause you already happen to know is a note, not the report.** Put it under `## Suspected` and
  mark it unverified. Phase 4 reproduces before theorising, and an authoritative-sounding cause in
  the issue body is exactly what makes it skip that.
- **Never guess `Expected`.** If the correct behaviour is genuinely unclear, spend one of Phase 0's
  two questions on it — a bug whose expected state is wrong sends the fix the wrong way.
