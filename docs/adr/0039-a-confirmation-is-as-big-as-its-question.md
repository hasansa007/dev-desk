# 0039 — A confirmation is as big as its question, and a survey reset asks about the cards it filed

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Amends [ADR 0021](0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md) §2 (every
dialog exactly 900 × 660).

## Context

The developer, 2026-09-16, on Reset survey: *"fix the reset survey"* and *"wonder what is expected of
cleanup all tasks maybe mention what in backlog to keep or to ignore"*. The sheet held four checkboxes in
a 900 × 660 frame, most of it blank, and two of the checkboxes were disabled on the project it was opened
on. Cancel task and Delete branch had the same shape. The reset also said nothing about the cards the
survey had put on the board, and those are what actually build up.

## Decision

- **`SheetChrome(size: .confirm)`** is 600 pt wide and as tall as its content. Reset survey, Cancel task
  and Delete branch use it. A card's dialog is still 900 × 660: 0021's rule was about cards, and a
  confirmation is not a card.
- **Reset survey lists every card its findings became.** Each is kept unless ticked. Only an issue nobody
  has started — no branch, not In progress, Review or Done — can be ticked, and a ticked one is closed as
  not planned with one shared reason (the same bounded write as Cancel task, ADR 0014). Started cards are
  listed with a warning to close them from their own card; a reset never closes work in progress
  (developer: *"no, but warn user"*). A card only in `docs/backlog/` is shown and kept.
- **The survey's source column names files** (`ContactDetailView.swift +1`), not a head-truncated path
  that had only line numbers left. Lines are in the tooltip, and By file still shows lines under the file.

## Rejected

```
rejected: fill the 900 × 660 frame with the card list alone — the other confirmations stay mostly blank
rejected: close started cards from the reset too — cancelling work under way belongs to that card
rejected: trash docs/backlog/ entries on reset — the developer answered "not exactly"; left open
```
