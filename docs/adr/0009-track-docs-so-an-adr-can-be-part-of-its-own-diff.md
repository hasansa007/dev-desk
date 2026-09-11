# 0009 — Track `docs/` so an ADR can be part of the diff that introduces it

Status:  Accepted
Date:    2026-09-10
Commit:  957da10  ·  `feature/tracker-and-pipeline-state`

## Context

`.gitignore` carried `/docs/`, commented *"Local working artifacts — ADRs, diagrams, survey reports.
Kept on disk, not tracked."* The result: **16 files under `docs/`, zero tracked.**

Among them were `0001-adrs-live-in-docs-adr.md` and `0002-diagrams-land-in-the-repo.md` — two ADRs
whose titles their own storage falsified. Neither was in the repo.

And `dev:docs`, the gate that owns ADRs, requires `docs/adr/NNNN-kebab-title.md` with *"`docs/adr/README.md`
… updated in the same commit"* and states plainly that **"the ADR is part of the diff."** Under
`/docs/` it could never be part of any diff. A gate whose artifact cannot reach a PR is prose.

## Decision

Remove `/docs/` from `.gitignore` and commit all 16 files.

The skills still probe `git check-ignore -q docs/` before writing into `docs/` in whatever repo they
run in — that check exists precisely because the answer differs per repo, and it now returns *not
ignored* here.

Consequence, documented in `documentation/CONTRIBUTING.md` rather than discovered: the
untracked→tracked transition changes the working tree in **both** directions. While this branch is
unmerged, `docs/` is tracked here and not on `main`, so checking out `main` removes 16 files from
disk. Unlike the 2026-09-07 incident this is recoverable — they are committed on the branch — but it
is still silent, and the window closes on merge.

## Rejected

**`git add -f` the one file that prompted this.** Smallest possible change, unblocks the work
immediately. Lost because it produces a repo where one spec is tracked and its seven ADR neighbours
are not, leaving the contradiction in place with a special case layered on top.

**Move design specs to `documentation/`, which is already tracked.** Consistent with the stated
rule, no `.gitignore` change. Lost because it splits specs from the ADRs they cite, and `dev:docs`
would still mandate an untrackable `docs/adr/` path — the contradiction survives the move.

**Leave everything untracked.** Honour the rule as written. Lost because the design work would have
no reviewable object, and ADRs 0001 and 0002 would go on being false.

## Later (2026-09-11)

`documentation/CONTRIBUTING.md` moved to `docs/guide/CONTRIBUTING.md` when the repo root was tidied
([ADR 0015](0015-files-live-with-the-flow-that-reads-them.md)); the Decision above keeps the path as
merged.
