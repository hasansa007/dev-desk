# 0027 — Work without a tracker is recorded locally, and promoted on request

Status:  Accepted
Date:    2026-09-13
Commit:  (this branch)  ·  `main`
Amends:  `docs/guide/GETTING-STARTED.md` — "Without [gh] there is no tracker, so the board and the filing doors cannot work"

## Context

A survey of a repository whose `origin` gh could not see produced fifteen confirmed findings and nowhere
to put them. "Add to backlog" ran `dev:create-issue`, which could not reach GitHub and retried in the
background until it was stopped; refusing the button instead left the findings unrecordable. The
developer asked: *"when there is no remote github — make the work local"*, and then *"what about the
local files when GitHub comes back — local, remote, or synced?"*

"No GitHub" is three situations — no remote at all, a remote gh cannot see, gh missing or signed out —
and the answer has to hold for all three.

## Decision

**A tracker when there is one; `docs/backlog/` when there is not; promotion only when asked.**

- With no reachable tracker, filing writes one markdown file per item to `docs/backlog/`, instantly and
  without an agent. A header the app reads back (`key`, `title`, `area`, `impact`, `complexity`,
  `source`, `issue`) sits above prose a person reads. The app never commits it.
- Entries are Backlog cards marked **Local**. They can be started — `/dev` takes a description as readily
  as a number — opened, or moved to the Trash.
- When a tracker is reachable, an entry offers **File on GitHub**. The run reads the file and files it;
  when it reports its issue, `issue: #N` is written into the file and the file moves to
  `docs/backlog/filed/`. From then on GitHub owns the item and the board shows the issue only.
- A promoting run that reports no number leaves the file where it is. Which issue it made is never guessed.

## Alternatives rejected

- **Local always owns it, GitHub mirrors it.** Every door in the family is built on GitHub being the
  tracker — `closes #N`, `gh-N-` branches, the milestone as the Queue column, `dev:kanban`. This would
  replace that everywhere, not in one screen, and an edit on github.com would be overwritten or drift.
- **Two-way sync.** No good answer to an item edited in both places, and the failure is silently
  rewriting an issue. Its cost is the largest of the three for a single developer's tool.
- **Promote automatically when a remote appears.** Pointing origin at a fork, or signing gh in as another
  account, is not consent to file fifteen issues there.
- **Refuse filing without a tracker** (the behaviour this replaces). The work was real and had nowhere to go.
- **Keep entries in `.dev/backlog/`.** Already ignored by git, so nothing appears in `git status` — and
  for the same reason invisible to anyone else, and lost when `.dev/` is cleared.

## Consequences

- The survey, Ideation and the board work the same with or without GitHub; only the destination changes.
- A file moved to `filed/` is history. Editing it changes nothing on GitHub, and nothing says so but this record.
- An issue filed by hand, outside the app, is not linked to its entry; both appear until the entry is removed.
