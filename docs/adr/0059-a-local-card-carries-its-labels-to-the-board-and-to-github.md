# 0059 — A local card carries its labels, to the board and to GitHub

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit), after 3c3bcc9

Amends [ADR 0027](0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md) — the header the
app reads back gains `priority`, `labels` and `type`. Applies [ADR 0020](0020-impact-and-complexity-are-labels-the-doors-propose.md)'s
"offer a missing label, never create it" to promotion.

## Context

Board's Priority, Type and Tag filters, the priority sort and the Bug/Epic kind all read `DeskTask.labels`. A
`docs/backlog/` card had none: `LocalBacklog.parse` read the fields 0027 listed and dropped the rest, though
`dev:findings` writes `priority: P1` and `labels: bug, search, impact:high` — or, in the cards it wrote on
2026-09-16, `type: bug` and no `labels:` line. A local P1 bug matched no filter and read as a Feature.

3c3bcc9 made `parse` read `labels:` and fold `priority:` in, and `localTask` pass them to the card. This record
covers that change and the rest of it.

## Decision

**A local card's labels are what its issue's would be, on the way in, on the board and on the way out.**

- **Read:** `labels:` (comma-separated, trimmed), plus `priority:` when it is P0–P3, plus `type:` when it is
  `bug` or `epic` — the two types that change the kind. Each added once.
- **Written:** `LocalBacklog.write` takes `labels` and `priority` and writes the same two lines a findings run
  does, the priority not repeated among the labels. "Add to backlog" from Findings passes `bug` for a defect.
- **Promoted:** File on GitHub asks `dev:create-issue` to apply the card's labels, each one the repository has,
  and to offer any it lacks — never to create one silently (ADR 0020).

## Alternatives rejected

- **Map `type:` to a label for every type** (`feature`, `task`). Lost because only bug and epic change what a
  card is; anything else already reads as a Feature, and inventing a `task` label adds one no filter reads.
- **Pass the labels to `gh issue create` from the app.** Lost because promotion is the door's run (ADR 0027), and
  the door is where the "offer, never create" rule already lives.

## Consequences

- A local card filters, sorts and shows its type the way an issue does.
- Add Task without a tracker can set the two lines, but its sheet still has no Priority or Type field; adding one
  is a sheet change of its own.
