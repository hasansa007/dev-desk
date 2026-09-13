# 0022 — Dev Desk deletes a local branch, and nothing else

Status:  Accepted — decision 1 and 4 amended by [0023]; the typed-name step dropped 2026-09-13 on request, one confirmation instead — [0023](0023-the-gate-ran-late-and-took-the-fold-with-it.md)
Date:    2026-09-12
Commit:  (this branch)  ·  `feat/desk-board-tracking-and-github`

## Context

The board opened on a real repository showed **19 cards in In Progress**, of which none was in progress.
They were finished `auto-claude/*` branches from runs that ended days earlier, plus
`backup/staging-unpushed-2026-09-11`, which is a backup and not work at all. Every one of them satisfies the
rule: a local branch holding commits the base does not is In Progress (`BoardBuilder.swift:210`, ADR 0011).

Two things made that worse than a miscount. The cards carried no date, so a branch last touched in March and
one last touched an hour ago read identically — even though the `for-each-ref` that lists them is already
sorted by committer date and was discarding it. And a card with no issue behind it had **no menu at all**:
`moves` is nil without an issue number, so nineteen cards could be read and nothing else. Cancel is defined as
closing a GitHub issue as *not planned*; a bare branch has none, so there was nothing to cancel with.

The developer's words were: *"in progress but not really — no cancel, no progress, no state update."*

ADR 0014 bounded what the app may write to a card's Move and Cancel, through `gh`. Nothing there reaches a
branch, and a board that cannot clear a dead branch cannot stop lying about it.

## Decision

**1. A branch card carries its age, and the board folds the dead ones.** `BranchFacts` keeps the committer
date the branch listing already sorts by. A card reads `6 commits ahead · 8 d ago`. A branch with no commit in
**14 days** is stale and folds behind a `Show stale (N)` toggle, the way Backlog already folds. Columns still
come from git: a stale branch is hidden, never re-columned, so ADR 0011 is untouched.

**2. Every column sorts newest-first**, so the live end of a column is always its top.

**3. A branch card gets its own menu**: open a terminal there, compare with the base, copy the name — and
delete the branch. A card with an issue keeps the tracker moves instead, so no card carries two menus.

**4. Dev Desk may delete a local branch.** This is the first thing the app destroys rather than moves. It is
bounded exactly as a tracker write is:

- one command, `git branch -d -- <name>`, its arguments built in `BranchWrite` and never interpolated into a
  shell;
- `--` ends the options, so a branch called `--force` is a name, not a flag;
- a name git would not accept — empty, containing a space, or a full `refs/` path — is refused before
  anything runs;
- `-d` is the default, and git itself refuses a branch whose commits are not in the base;
- **`-D` is reached only after the developer has typed the branch's own name** into the sheet, which also
  states how many commits would be lost;
- **local only.** A branch pushed to GitHub stays there. The app has no remote delete and this ADR does not
  give it one.

## Consequences

- **The board can now be wrong in a new way**: a stale branch someone is about to return to is hidden until
  `Show stale` is pressed. The count in the toggle is always visible, so nothing disappears silently.
- **Fourteen days is a guess**, not a measurement. It is one constant, `BranchAge.staleAfter`, so it can be
  moved when the repository says otherwise.
- **ADR 0014 still holds for the tracker.** Move and Cancel remain the only issue writes; this adds a git
  write, not an issue one, and deliberately does not add "delete the issue" alongside it.
- **A worktree's branch cannot be deleted** — git refuses a branch that is checked out, and the error it gives
  is shown as written rather than interpreted.

## Alternatives rejected

```
rejected: re-column stale branches into their own column — the columns are git's, and git has no such column
rejected: hide stale branches outright — a board that silently drops rows is worse than one that over-reports
rejected: an age threshold per repository, in Settings — a preference for something nobody has yet had an
          opinion about; one constant until someone does
rejected: delete the remote branch too — the app would destroy something shared, from a card, in one press
rejected: -D with a plain confirm button — the same two words for "this loses nothing" and "this loses six
          commits" is how a confirmation stops being read
```
