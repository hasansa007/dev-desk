---
name: dev-review
description: >
  Handle human review feedback on an OPEN pull request — fetch the comments, restate each one,
  push back with technical reasoning where a suggestion is wrong, implement one item at a time,
  then commit and push back into the pre-merge gates.
  Trigger when the user says "changes requested", "fix the PR comments", "review feedback",
  "address the review", or pastes a PR URL that has a review on it.
  This is a LOOP back into the merge gates, not a stage after them.
allowed-tools: [gh, git]
---

# Dev — Review Cycle

Standalone entry into **Phase 10.2 — Review Cycle** of the dev pipeline.

## This is a loop, not a stage

Review comments arrive while the PR is still **OPEN**. This skill's last step is `push`, never
`merge` — you re-enter Phase 10's pre-merge gates and go round again until the review is clean.

```
dev-pre-prod (Phase 10)  push → PR → gates → merge → PRE PROD
                              ↑              │
dev-review   (Phase 10.2) ────┘  fix → push  │   ← loops back, never forward
                                             ↓
dev-prod     (Phase 10.5)              promote → PROD
```

It runs **before** pre prod, and long before any production promotion. If you reached for this
after a prod release, you want a new branch and a fresh `/dev` run, not this.

## Input

A PR number or URL that has review comments on it.

## Run

1. Read `~/Developer/dev-skill/shared/entry.md` and apply it.
2. Read `~/Developer/dev-skill/shared/pipeline.md` → execute **Phase 10.2 — Review Cycle**.
3. After the fixes land and are pushed, **return to Phase 10's pre-merge gates** — the diff
   changed, so the review that was clean no longer is.

## The protocol

Follow `receiving-code-review` — technical rigor, not performative agreement:

- **Restate each requirement in your own words** before touching anything
- **Check it against the actual codebase** — a reviewer can be wrong about what the code does
- **Push back with reasoning** when a suggestion breaks existing behavior, violates YAGNI, or
  conflicts with established architecture. Agreeing with a wrong review costs more than the
  disagreement does.
- **Implement one item at a time**, with testing between

## Guards

- **New commits, never `git commit --amend`.** Reviewers need to see what changed since their pass.
- **Never force-push** without an explicit request.
- **Re-verify if logic changed.** Re-run the affected Phase 9 rows (`dev-verify`) — cosmetic-only
  fixes (comments, imports, formatting) can skip it.
- **Re-run the docs gate if the fixes touched a number, a decision or an env var** (`dev-docs`).
  Review fixes are a classic way for an ADR to drift out of date silently.
- Ask for confirmation before implementing: *"Here's the plan to address the review comments.
  Proceed?"*
