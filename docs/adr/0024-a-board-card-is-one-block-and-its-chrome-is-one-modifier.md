# 0024 — A board card is one block, and its chrome is one modifier

Status:  Accepted
Date:    2026-09-12
Commit:  (this branch)  ·  `feat/desk-install-script-and-one-card`
Amends:  0023 (decision 6 — one anatomy is not yet one card)

## Context

ADR 0023 decision 6 gave every card the same *rows*. A screenshot of the result shows that is not the
same as the same *card*: a three-line title made one QUEUED card half again as tall as its neighbour,
a startable card reserved an action row that a branch card did not, and the columns read as four
ragged lists rather than four columns.

The style had drifted too, and further than the board. `TaskCard` drew its own surface, border,
selection ring and a corner radius of **9** — while `DeskMetric.cardRadius` is **8** and a
`deskCard()` modifier already existed in `Primitives.swift` and was simply not used. Two sheets had
copied the same literal 9. A shared modifier that the most-used card ignores is not a shared modifier.

The developer's words, against a screenshot of the board: *"See difference between cards sizes and
styles — be reusable."*

## Decision

**1. Every board card is exactly one block.** `DeskMetric.cardContentHeight`. The title is clamped to
two lines and reserves two lines whether or not it needs them, so a long title truncates instead of
growing the card.

**2. The note and the action share one reserved band at the bottom.** Reserving them as two separate
rows — the first attempt — left every card without an action visibly half-empty, which traded a
ragged column for a sparse one. One band is reserved on every card: the note reads along it, the
Start control sits at its right, and the note is inset so the two never overlap.

**3. Card chrome is `deskCard(padding:border:isSelected:)` and nothing else.** Selection moved into
it, so the accent border and its halo are drawn the same way wherever a card can be selected. The
literal radii in `CompareOutputsSheet` and `ReconcileFindingSheet` are now the token.

## Consequences

- **A long title is now truncated on the board**, and the full text is one click away in the dialog
  that every card opens (ADR 0021). Before, it was legible on the board at the cost of the column.
- **A card carries a little slack when it has neither note nor action.** That is the price of a
  uniform grid, and it is one constant to tune rather than a layout to re-derive.
- **A column header is one line at one height too**, for the same reason one row lower down: a theme
  whose title wrapped — "Milestone · Tracker truth — one authoritative backlog" — made its own column
  start a row below the two beside it. It truncates with the full title on hover, and the board's
  column headers take the same height so it cannot come back there.
- **The next card-shaped surface has one thing to call.** The drift this ADR removes happened because
  copying four lines of chrome was easier than finding the modifier that already existed.
- **`deskCard` now sets `contentShape` for all twelve of its call sites**, not just the board's. Traced
  through each — `SurfaceView`, `RequirementsTab`, `IdeationScreen`, `FindingDetail`, `TaskNoticeViews`,
  `EvidenceTab`, `RoadmapScreen` — and nothing depends on the old hit region: children keep their own,
  so text selection still works. Recorded because it is a behaviour change riding in a refactor.

## Alternatives rejected

```
rejected: a fixed height with three-line titles — the extra line is spent on the few long titles and
          charged to every card in the column
rejected: per-column card variants — the columns are git's, not the card's; a card that knows which
          column it is in is a card that will drift again
rejected: leave the note and action as separate reserved rows — measured on screen, it made every
          card without an action look broken rather than uniform
rejected: shrink to fit the shortest card and let long titles overflow — clipping text is worse than
          truncating it, because nothing tells the reader it happened
```
