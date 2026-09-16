# 0041 — A survey reset clears the findings and what they filed, and keeps work in progress

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Reverses [ADR 0039](0039-a-confirmation-is-as-big-as-its-question.md)'s reset rules (only untouched issues
closable, `docs/backlog/` cards kept) and 0029's "the newest report is always kept".

## Context

The developer, 2026-09-16, on the Reset survey sheet: *"why reseting it, is not cleaning up all tickets"*,
then *"move all tickets to trash"*, *"for local, for remote if it's an issue then close with reason while not
in progress — all inprogress resume or warn"*, and *"i expect that reset survey will clean up the findings"*.
On a project with no remote every filed card was a `docs/backlog/` file, so the reset could remove nothing,
and keeping the newest report kept every finding on screen.

## Decision

- **Clear the findings:** every report in `docs/survey/` goes to the Trash, the newest included. On by default
  when there is one; refused while a survey is running.
- **Each filed card, by what it is** (`FiledCardReset`):
  - a `docs/backlog/` entry not in progress, Done included → the Trash;
  - a GitHub issue not in progress → closed as not planned, with the shared reason;
  - a GitHub issue already Done → nothing;
  - in progress (a branch, or In progress / Review), local or remote → kept, warned, and offered **Resume**
    (Terminals when its session is live, otherwise the start sheet).
- Everything that can go **starts ticked**: the reset was opened to clean up. Untick to keep.

## Rejected

```
rejected: keep the newest report — the findings the developer asked to clear stayed on screen
rejected: remove in-progress cards too — a reset never takes work under way; it warns and offers Resume
rejected: stash instead of Trash — docs/backlog/ removal already uses the Trash (ADR 0027); one undo, not two
```
