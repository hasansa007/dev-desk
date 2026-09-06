# 0007 — Raise the pipeline line ceiling to 988, and install the check

Status:  Accepted
Date:    2026-09-06
Commit:  f5adbd3  ·  PR #25

## Context

`GUIDE.md` caps `shared/pipeline.md` at 958 lines: *"at the ceiling, an addition is only allowed with
a deletion in the same commit."* The walkthrough gate (`0006`) added 30 lines and shipped anyway.

Four PRs (#19–#23) breached a hard rule with nothing firing, because `GUIDE.md`'s own claim —
*"`ci/pr-gates.yml` now recomputes this rather than trusting the integer written here"* — was false
in practice. That file has **never been installed**; there is no `.github/workflows/` in this repo.

A ceiling whose only enforcement lives in an uninstalled file is prose.

## Decision

Ceiling moves 958 → 988: the smallest raise that admits the change, with zero slack, per the
2026-08-24 correction. The next addition pays again.

The `line-budget` job is installed on its own at `.github/workflows/line-budget.yml`.

## Rejected

- **Delete Phase 11's capture block, delegating to `dev:shots`** — the deletion the README has named
  as pending for weeks. Does not pay: `dev:shots` owns the capture *commands*, but Phase 11 only
  points at them, in two lines.
- **Delete the 27-line teardown block** — `dev:launch-kill` does not cover the MCP-launched Chrome,
  so that rule lives nowhere else and Phase 11 is its point of use. Per 2026-08-23, relocating a rule
  away from its point of use is not a deletion and would not have paid either.
- **Raise to a round 1000** — 2026-08-24 already corrected that instinct: a ceiling with slack is not
  a ceiling.
- **Install all of `ci/pr-gates.yml`** — its `required-sections` job demands a `## PIPELINE` body,
  and PRs opened against this repo are not `/dev` runs. It would fail every PR here. The
  `line-budget` job shares none of that: it reads three files and compares three numbers.

## Consequences

The file is ~3% longer and attention per rule drops accordingly — the cost the ceiling exists to
price. The check now runs on every PR and every push to `main`, so the next breach is loud.

The check greps `README.md` for the literal string `"<actual> against a <ceiling>-line budget"`, so
three numbers must agree across two files or it fails. That is deliberate: the defect it was built
for was three wrong counts asserted from memory in three consecutive PRs.

## Evidence

```
PASS: pipeline.md 988 / 988 — GUIDE and README agree.
```

Before the fix: `actual 988 · ceiling 958 · stated 958 · README "958 against a 958-line budget"` —
three of four disagreeing, and nothing running to notice.
