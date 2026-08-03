---
name: dev-pre-prod
description: >
  Take finished work to PRE PROD — push, open the PR, run the pre-merge gates (docs, code review),
  then merge to the pre-prod branch (`staging` in studyhub-deploy). Ends at pre prod, never at
  production.
  Trigger when the user says "open a PR for this", "PR this branch", "merge to staging", "take this
  to staging", "ship this to pre prod", or when work is finished and needs to reach the shared
  environment. NOT for promoting staging to production — that is `dev-prod`.
allowed-tools: [gh, git]
---

# Dev — Pre Prod

Standalone entry into **Phase 10 — PR Creation → Review → Merge → Pre Prod**.

## Input

A branch with the work committed. The base is the **pre-prod branch** resolved by
`shared/entry.md` — never assume it.

## Run

1. Read `~/Developer/skills/dev-skill/shared/entry.md` and apply it. **State the resolved base branch
   before doing anything** — getting this wrong means a PR that never deploys.
2. Read `~/Developer/skills/dev-skill/shared/pipeline.md` → execute **Phase 10** in full, including the
   `Phase 10 Additions` from `dev/SKILL.md` when the source is a GitHub issue (`Closes #N`, labels).

## The sequence

**push → PR → review → merge → pre prod**, in that order.

The review is a **HARD GATE**: never merge an unreviewed diff — not when running the whole
sequence autonomously, not for a one-line change.

**Pre-merge gates, all required:**

0. **Phase 9.4 — docs & ADRs** (`dev-docs`). Prices, limits, decisions with rejected
   alternatives, env vars, migrations and deferred work recorded BEFORE the merge.
1. **Phase 9.5 review** — `/code-review` + a spec-compliance check against the full PR diff.
   Add `security-review` when the diff touches money, auth, migrations, uploads, or untrusted input.
2. Fix every **Critical** and **Important** finding; re-verify if logic changed.
3. **Do NOT merge** while any Critical/Important finding is open. "It's small / I already
   self-reviewed / tests pass" does not waive this.
4. Review clean **and** the developer confirms → merge → pre prod.

## Guards

- **This ends at PRE PROD, not production.** Do not report the work as "shipped" or "live". If the
  repo has a two-stage model, production is `dev-prod` (Phase 10.5) and it has its own gate.
- **The runbook overrides this sequence.** If `docs/deploy-and-staging.md` or similar exists, read
  it — some repos release prod on the merge itself, in which case this skill IS the prod release
  and needs the Phase 10.5 confirmation instead.
- **Carry the verification evidence into the PR body.** `## VERIFICATION`, `## DOCS`, and
  `## HOW TO TEST` are required sections — the checklist left in chat is a failed Phase 9.
- Never add `Co-Authored-By` trailers or AI-attribution footers.

## Next

`dev-review` (Phase 10.2) if reviewers request changes — it loops back into these gates.
`dev-prod` (Phase 10.5) to promote, later, as a separate decision.
