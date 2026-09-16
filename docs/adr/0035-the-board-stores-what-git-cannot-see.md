# 0035 — The board stores what git cannot see

Status:  Accepted, amended by [0037](0037-a-local-card-carries-its-own-done.md)
Date:    2026-09-15
Commit:  (uncommitted)  ·  working tree

Partially reverses [ADR 0011](0011-the-project-board-mirrors-it-never-decides.md) ("the Project
board mirrors; it never decides").

## Context

The board's columns were computed purely from git and GitHub facts: an open PR ⇒ Review, a branch
with unmerged commits ⇒ In progress, the active milestone ⇒ Queued, else Backlog. A *run* never
entered that decision, so a card could sit in **Backlog with a pulsing "Running" pill** — which is
what the developer reported. There was also no way to say "this is ready to be worked on": the
milestone was the only signal, and it cannot express "started but nothing committed yet" — the gap
between pressing Start and the first commit, where git has nothing to say.

ADR 0011's real objection to stored board state was that a stored Status field can disagree with
git and *looks* authoritative while doing it. That objection is about the columns git computes, not
about the lifecycle git never sees.

## Decision

**Dev Desk stores the part of the board git cannot see, and only that part.** A new file,
`.devdesk/board.json` (`BoardStages`), records three stages per card: `readyForDev`, `queued`, and
a started card's `inProgress`. The full lifecycle:

```
Backlog  →  Ready for dev  →  (Queued)  →  In progress  →  Review  →  Done
             ↑ cancel → Backlog           ↑ cancel → Ready for dev   ↑ back → In progress
```

The boundary that keeps 0011's objection answered:

- **Git still decides In progress (unmerged commits), Review (an open non-draft pull request) and
  Done (merged).** `BoardBuilder` consults the stored stage only after every git rule has declined,
  so a stage can only ever fill the gap before the first commit, never contradict a fact. Moving a
  card back from In progress is refused outright once commits exist, with the reason named.
- **Review → In progress goes through the pull request**, not around it: the card's move converts
  the PR back to a draft (`gh pr ready --undo`), so the column changes because the fact it reads
  changed. A draft PR reads as In progress for the same reason.
- The file is **machine-local bookkeeping, never a second authority over git.** Stages recorded
  under `branch:`/`pr:`/`merged:` ids are ignored; a missing or corrupt file reads as empty and
  every card falls back to what git and the milestone say.
- The active milestone now puts an issue in **Ready for dev** (the old Queued rule); Queued means
  "waiting for a free agent slot". A Start pressed with no slot free parks the card in Queued
  instead of refusing it, and the queue releases cards in board order as slots free — against the
  same app-wide count and limit Auto measures itself with, so a manual Start and Auto cannot
  disagree about whether the app is full, and the queue drains whether or not Auto is on. Done
  keeps no backwards move — a revert flow is deliberately deferred.

## Rejected

- **GitHub labels as the stage store.** A label needs an issue and write access, so a
  `docs/backlog/` card (ADR 0027) could never carry a stage, and every move would be a network
  write that can fail or lag the board.
- **Keeping the milestone as the only signal.** It cannot express "started but nothing committed
  yet", which is exactly the gap the developer's report fell into, and it gives local cards nothing.

## Consequences

- The board is no longer purely recomputed: `.devdesk/board.json` is the first board state the app
  *stores* rather than derives. The write path never throws (`ProjectRunState`'s shape); the model
  reads the file back and reports a stage that did not land.
- `scripts/dev.py`'s own board is deliberately **not** changed, so `dev board` still shows the old
  four columns — the two-reader divergence `PROJECT_MAP.md` already documents grows by one rule.
- Auto starts from Ready for dev, which is where planned work sits now.
