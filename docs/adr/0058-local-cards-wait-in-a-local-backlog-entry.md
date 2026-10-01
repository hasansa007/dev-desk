# 0058 — Local cards wait in a Local backlog entry, and under All when there is no tracker

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit)

Amends [ADR 0046](0046-one-task-model-three-views-findings-keeps-its-name.md) decision 13 ("the milestone list
IS the backlog"). Extends [ADR 0027](0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md).

## Context

Decision 13 removed Board's Backlog column: unstarted work waits in its milestone's entry on the left, and the
first column holds only what is Next up. That holds for an issue, which always has an entry — its milestone or
No milestone. A `docs/backlog/` card has neither. `BoardBuilder.localTask` puts a card with no stored stage in
`.backlog`; `inWorkScope` admitted only issue cards to No milestone; and under All the first column takes no
backlog at all. So a fresh local card was on **no** column of any selection.

Found 2026-10-01 in a repository with no remote, after a `dev:findings` run filed its cards locally: the cards
were in `docs/backlog/` and nowhere on Board. The workaround was writing `"local:<id>": "readyForDev"` into
`.devdesk/board.json` for every card, which claims a decision nobody made.

## Decision

**A local card waits in an entry of its own, Local backlog, beside No milestone — and under All when there is no
tracker, because then there is no list for it to wait in.**

- `WorkScope.localBacklog` (key `TaskFilter.localBacklog`) selects every local card, started or not, as a
  milestone selects its issues. Its first column is **Not started**, and it combines with milestones like any
  other chip.
- The entry is listed while any local card is open (or while it is selected), with its open count.
- **No reachable tracker** (the same test Add Task uses, `TaskDestination`): there are no milestones, so the
  list cannot be the backlog. All's first column then also takes local cards with no stage and is titled
  **Not started**; the header reads "All tasks · N open". Branch cards stay where they were.
- Nothing about an issue card changes: No milestone is still issues filed nowhere, and All with a tracker still
  shows no backlog.

## Alternatives rejected

- **Local cards are Next up by default when there is no tracker.** Smallest change, and it would have hidden the
  report's symptom. Lost because Next up means someone chose it; a findings run's twelve cards would all claim
  that, the stored `readyForDev` stage would stop meaning anything, and with a tracker present the cards would
  still be invisible.
- **A Backlog column that appears only when local cards exist.** Visible everywhere at once. Lost because it
  reverses decision 13 for one kind of card, and a column that comes and goes with the data moves the board
  under the developer.
- **Default the selection to Local backlog when there is no tracker.** Lost because that selection hides branch
  and report cards, which a repository with no tracker shows under All today.

## Consequences

- A local card is visible with no `.devdesk/board.json`; the workaround is no longer needed.
- In a tracked repository, local cards waiting for File on GitHub no longer sit in no column. They are one click
  away rather than on the default Board, as an issue in another milestone is.
- `inWorkScope` and `inWorkColumn` read whether a tracker is reachable, so the same card can sit in a different
  place in the same repository once `gh` signs in. That is intended: the list it waits in has appeared.
