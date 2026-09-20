# 0011 — The Project board mirrors; it never decides

Status:  Accepted, partially reversed by [0035](0035-the-board-stores-what-git-cannot-see.md)
Date:    2026-09-11
Commit:  (this branch)  ·  `feature/tracker-and-pipeline-state`

Amends the design spec's §4, which recorded *"No GitHub Project v2 board"* as a non-goal.

## Context

`dev:board` renders the board as text. The recorded decision against a GitHub Projects v2 board had
two reasons: the `project` token scope is not granted here, and **a Project board stores state that
can disagree with git.**

The second reason is the real one. Every column `dev:board` shows is *recomputed* from `git` and
`gh` on each run and therefore cannot be stale — that property is why 4.4's precedence rule exists
(*"git wins and the row says the state file disagreed"*). A stored Status field is exactly the class
of value that rule was written to distrust, and it is **more** dangerous than `.dev/` phase state,
because a board you can drag looks authoritative in a way a JSON file never does.

But the first reason was never a real objection: a missing scope is a prerequisite, not a design
constraint. And a visual board is genuinely useful.

## Decision

Add the adapter, with the direction of trust fixed: **the Project board is an output, never an
input.**

- Columns are computed exactly as before, then **pushed** to the project's Status field.
- Project status is **never read back as truth.** It is read only to compute the difference, and to
  report drift.
- **Dry run by default.** `--apply` writes, matching `dev run`'s shape and for the same reason: this
  mutates something outside the repo.
- **It never invents a Status option.** A column with no matching option is reported as unmappable
  and skipped. Creating options silently would let the adapter reshape someone's board.
- **Optional everywhere.** `doctor` reports Projects v2 availability on a row that never counts as a
  failure; without the scope the adapter says so and everything else works unchanged.

The planning core is pure — computed board plus current project items in, the edits needed out — and
fixture-tested, because the live path cannot run without a scope this machine does not have.

## Rejected

**Read the Project's Status as the source of truth for a column.** This is what a normal Projects
integration does, and it is what makes the board feel real: you drag a card and the system believes
you. Lost because it makes the picture and git two authorities with no tiebreak, which is the exact
failure 4.4 forbids for a file nobody can see. If you drag a card, the next `dev project` run moves
it back — that is the adapter working, not a bug.

**Create missing Status options automatically.** Convenient, and it makes the first run "just work".
Lost because it edits the shape of a board the family does not own, from a run the developer started
for a different reason.

**Make `queue` mean "the Queue column" rather than the active milestone.** Tempting once a board
exists. Lost because the milestone is readable by every other door and by `gh` without a scope,
while a Project column is readable by neither.

**Keep the non-goal.** Still defensible — nothing needs this. Lost because the objection that
mattered is answered by making the board write-only, and the objection that did not matter (a token
scope) was never a reason to design around.
