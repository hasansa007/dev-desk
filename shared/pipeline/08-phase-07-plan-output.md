## Phase 7 — Plan Output

> Phase 5 already settled *what* to build and, for UI work, *what it looks like*. This phase is
> only the written plan. If you arrived here without that go-ahead, go back.

### Scale the plan to the work — a spec FILE is not always the artifact

A ten-section spec written to `specs/` is right for work that will outlive this conversation. It is
ceremony for a task that finishes in one sitting, and ceremony is what gets the phase skipped.

| Write | When |
|---|---|
| **An inline plan** — 3–6 lines, in the response | the work finishes this session and nothing needs handing over |
| **A spec file** (`specs/[slug].md`, full template below) | **REQUIRED** when any of: the work spans sessions · someone else will pick it up · Phase 6 ran, so rejected alternatives must survive to Phase 12's ADR · the plan itself is the deliverable |

Say which you chose and why, in one clause. **Silently producing neither is the failure this rule
closes** — observed 2026-08-04, when a 14-file rename ran end to end with a 4-line inline plan, no
spec file, and nothing in the pipeline noticed the template had been skipped.

Use the `writing-plans` skill to create the plan (seeded by Phase 6's winning approach when that
phase ran). Whichever form it takes, it must include:

- **Exact file paths** for every file to be created or modified
- **Concrete code blocks** showing what changes (no placeholders like "add error handling" or "TBD")
- **Granular tasks** — each task should be 2–5 minutes of focused work, not hours
- **Success criteria** — what "done" looks like (from Goal-Oriented Execution)
- **PROJECT_MAP.md update** — what changes to `TECH_STACK`, `SYSTEM_FLOW`, or `ORPHANS & PENDING` are needed

```
## <TICKET / ISSUE / FEATURE>: Summary
Type | Priority | Branch | Base

## Understanding
1–2 sentence plain-language summary

## Root Cause / Approach
hypothesis (bugs) or design direction (features)

## Success Criteria
what the user sees / what tests pass / what counts as done

## File Map
which files will be created / modified and why

## Implementation Plan
numbered tasks — exact file paths — concrete changes per task

## Effort Estimate
Total estimated effort in hours

## Clarifications Needed
questions to resolve before starting

## Testing Checklist
unit + manual + regression

## PROJECT_MAP.md Impact
changes to TECH_STACK, SYSTEM_FLOW, or ORPHANS & PENDING

## PR Notes
what to call out in review
```

If the table above called for a spec file, write it to `specs/[feature-slug].md` now. If it called
for an inline plan, the plan above IS the artifact — do not create a file nobody will read.

After presenting the plan: ask "Any clarifications or changes before I start implementing?"

---

