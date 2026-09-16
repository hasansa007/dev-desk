# 0038 — The survey is a triage list, and the board's controls live on their columns

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Amends [ADR 0021](0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md) §8 (where Side
by side sits) and [ADR 0020](0020-impact-and-complexity-are-labels-the-doors-propose.md) (the dash on an
unrated card, for findings only).

## Context

The developer, 2026-09-16, on the board header: *"i did not like this top show backlog and that side by
side one"*, and on the survey: *"i did not like the survey tasks display and ui"*. Seven layouts were
drawn as mockups; the developer chose the recommended pair.

What the screenshots showed:

- **Show backlog** was an on/off switch styled as a button. **Side by side** sat at the far right of the
  header, disabled whenever fewer than two tasks run — most of the time — a screen's width from the
  column it acts on.
- **The survey grid** gave 26 findings 26 same-sized cards. "Code-inspected · confirmed by review"
  repeated on 16 of them, `impact —` / `complexity —` on all 26 (a survey rates nothing; 0020's rating
  arrives only when a finding is filed), and titles — the finding itself — truncated at two lines.
  Status and kind filters shared one chip row, and a Backlog button sat on every card.

## Decision

**Board.**
- The header holds the title, search and the rules button, nothing else.
- The backlog, when hidden, is a 34 pt rail at the board's left edge with its count; clicking opens the
  column, and the column's own chevron closes it. `model.showBacklog` is unchanged underneath.
- **Side by side moves into the In progress column header**, and appears only when two or more tasks
  there can run side by side. 0021 §8's "on the board it affects" still holds — now on the column it
  affects — but the disabled-with-a-tooltip state is gone: a control that is unavailable most of the
  time was noise most of the time.

**Survey.**
- One row per finding: checkbox, full-width title, kind, area, source, and an action slot that shows a
  state (Filing…, Filed, In backlog, Ignored) always and the Backlog button and ⋯ menu on hover.
- Rows are sectioned **By status** (New, Known · new evidence, Needs a decision, Closed or declined —
  a finding with two categories under the first) or **By file** (busiest file first; a finding appears
  under every file it names; bare names and paths to the same file are one section). The choice is
  remembered in `desk.surveyGrouping`. Grouping lives in `DeskCore` (`FindingGroups`) and is tested.
- A section header says what the section means and, when every row agrees, how far it was verified —
  once. Its checkbox selects the section; a bar at the bottom files or ignores the selection, skipping
  any finding already filing, filed or in `docs/backlog/`.
- Status chips are gone (the sections are the status). Kind is a segmented control; Ignored stays a chip.
- **Impact and complexity are not shown on a finding until it is tracked by an issue** — row and
  dialog. 0020's dash still marks an unrated *issue* on the board; on a finding the dash could never
  be anything else, so it said nothing.

## Rejected

- **Board: Backlog and Board as two tabs.** Suits a long backlog, but a card could no longer be seen
  beside Ready for dev, which is where it moves to.
- **Board: one View menu** holding both controls. The quietest header, and Side by side undiscoverable.
- **Survey: list with a detail pane and keyboard triage.** The evidence beside every decision; but the
  reading pane is what the card grid had replaced, for making a finding something read rather than
  acted on, and the dialog already carries the evidence one click away.
- **Survey: triage columns** (New / Needs a decision / In backlog / Ignored) with drag to file. Matches
  the board; sixteen drags to file sixteen findings, and four columns truncate titles again.
- **Keep the card grid, trim the card.** Removes the repetition but not the truncation, and still fits
  about nine findings on a screen where a list fits twenty.

## Consequences

- `FindingCard` and `DeskMetric.findingCardHeight` are removed; `FindingRow` carries the filing logic
  the card had.
- Batch filing starts one `dev:create-issue` run per finding, as single filing always did — the run
  limit applies to them the same way.
- Snapshot mode captures `03a-survey-by-file` and `03c-board` (the collapsed rail).
