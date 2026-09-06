# 0004 — Compare cited paths, not the whole tree, before advancing a pin

Status:  Accepted
Date:    2026-08-31
Commit:  eba28cb  ·  PR #22

## Context

A squash or rebase merge rewrites a branch's commits, so a diagram pinned to the branch tip becomes
unreachable and a fresh clone fails `repository-evidence/revision-unavailable`. It keeps validating
on the machine that built it, because the orphaned object survives in `.git` until `gc` — green
locally, broken for everyone else.

The rule added to handle that (`PR #20`) required **whole-tree equality** before re-pinning. That is
unsatisfiable by construction: the artifact lives in `docs/arch/`, so committing it guarantees the
trees differ. The check would have said "re-read" on every merge forever, and
`ci/pr-gates.yml` already records what that produces — *"a check that fires on correct work is how a
check gets ignored."*

## Decision

Before advancing a pin, intersect the IR's `sources[].path` set with
`git diff --name-only <old-pin> HEAD`. An **empty intersection** means the new commit holds
byte-for-byte the code that was read, so the pin may advance and states no new claim. A **non-empty**
one means re-read those ranges — including for line shifts, not only deletions.

Better still, avoid the problem: a branch that touches no cited path should pin to the **base
branch's HEAD**, which is already an ancestor and survives every merge strategy.

## Rejected

- **Whole-tree equality** — the previous rule. Never satisfiable once the artifact is committed
  alongside; see above.
- **Forbid squash merges** — fixes it, but that is a repo-wide policy change to serve one artifact.
  Wrong blast radius.
- **Pin to a tag instead of a SHA** — tags move. Immutability is the entire point of the pin.
- **Drop pinning** — deletes the feature that makes an evidenced diagram worth more than prose.

## Consequences

Re-pinning after a merge is now a routine, checkable step rather than a judgment call. The first
landing of any diagram whose branch changed cited code still needs an after-the-fact re-pin, because
the correct pin cannot exist until the merge lands.

## Evidence

Measured on PR #21's own merge:

```
orphaned pin tree  d60741d8...          main HEAD tree  d59173f3...      <-- differ

git diff --name-only b29afda HEAD
  docs/arch/dev-family.architecture.json          <-- the artifact
  docs/arch/dev-family.html                       <-- the artifact

cited paths: 22        cited paths that differ: NONE
```
