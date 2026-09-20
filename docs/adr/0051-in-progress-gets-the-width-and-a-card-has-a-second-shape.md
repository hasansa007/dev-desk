# 0051 — In progress gets the width, and a card has a second shape

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Reverses one rejected alternative in [0024](0024-a-board-card-is-one-block-and-its-chrome-is-one-modifier.md):
*"rejected: per-column card variants"*. The rest of 0024 stands — a card is still one block, its title is
still clamped, and its chrome is still `deskCard` and nothing else.

## Context

0024 rejected per-column variants because *the columns are git's, not the card's*. That reasoning held
while every column was the same width and the board was four equal lists. The Focus layout is the
opposite claim: the columns are **not** equal, because attention is not equal. In progress is where work
actually is, and on a 1440 pt board it was one 300 pt column of the four, showing the same truncated
two-line title as a card nobody has started.

A wide column with a card drawn for a narrow one is worse than either: the card keeps its 300 pt shape
and floats in the space, which is how the first attempt looked.

## Decision

**1. The columns are weighted.** Next up and Review are 248 pt, In progress takes all remaining width,
and Done is a 52 pt strip at the right edge that opens into a column. A strip, because Done is a place you
confirm something reached, not a place you work.

**2. A card has two shapes, not a shape per column.** `TaskCard.Variant` is `.standard` and `.focus`. It
is still one component with one `deskCard` chrome, one menu, one Start path and one accessibility
description; the variant changes the title size, the meta it can afford, and whether the run's last line
fits. Every card *within* a column is still identical, which is the ragged-column failure 0024 was
written against.

**3. The card that needs you is the only outlined box on the board.** Column surfaces and borders are
gone — cards sit on the board's ground — so the waiting amber outline has nothing competing with it. A
live run carries the running green; everything else keeps the hairline.

## Consequences

- **The variant must stay tied to the stage, not to the width.** A `.focus` card in a narrow column would
  re-create exactly the drift 0024 removed. It is drawn in In progress and nowhere else.
- **`DeskMetric.boardColumnWidth` (300) no longer sizes the board.** Left in place, unused, until the
  Design owner retires it.
- **Batch filing on Findings is gone** with the one-at-a-time layout — recorded in 0052, not here.

## Rejected

- **Keep four equal columns and make the card taller in all of them** — the extra height is spent on the
  one column that needs it and charged to the three that do not, which is 0024's own argument.
- **A separate "focus" screen for In progress** — a second place to look at work you are already looking
  at, and the board stops being the board.
