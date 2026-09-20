# 0048 — The Board drops the P0 strip

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Reverses ADR 0046's P0 strip on the Board — the red band reading *"N P0 in other milestones · Show all"*
while a milestone filter is on. The rest of 0046 stands, including a P0 being pinned into Next up
whatever its milestone.

## Context

The strip answered "a narrowed board must not hide an emergency". In use it sat above every filtered
board as a permanent red band, and on 2026-09-20 the developer, reading it on their own board, asked
what it was for — a warning nobody can identify is not a warning. The developer: *"remove that strip"*.

The worry it addressed is already covered: a P0 is pinned to the top of Next up whatever its milestone
(0046 decision 1), the Priority group counts P0 across the whole tracker, and the milestone filter is
one click from off.

## Decision

- **The Board shows no P0 strip.** `p0Strip` and `ProjectWindowModel.p0OutsideWorkScope` are removed
  rather than hidden behind a setting: a band nobody could name does not become useful by being optional.
- **Nothing replaces it.** The board is the cards the filter selects, and the filter says what it selects.

## Rejected

- **Keep it, worded better** — the band's cost is that it is always there, not that it was unclear.
- **A count on the Priority group instead** — the group already counts P0 under the current filters, and
  a second count with different scoping beside it is the confusion this removes.
