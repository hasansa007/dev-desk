# 0037 — A local card carries its own Done

Status:  Accepted
Date:    2026-09-16
Commit:  6efdef2

Amends [ADR 0035](0035-the-board-stores-what-git-cannot-see.md) ("the board stores what git cannot
see"). Extends [ADR 0027](0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md).

## Context

ADR 0035 drew the boundary that keeps [0011](0011-the-project-board-mirrors-it-never-decides.md)
answered: git decides In progress (unmerged commits), Review (an open pull request) and **Done
(merged)**, and `.devdesk/board.json` may only fill the gap before the first commit.

For an issue card that is right. For a `docs/backlog/` card (ADR 0027) it is a rule that **can never
fire**. A local card has no branch and no pull request by construction — that is what "local" means —
so git has no opinion available about it, ever. `BoardBuilder.localTask` read its column purely from
the stored stage, whose three values are `readyForDev`, `queued` and `inProgress`. There was no
fourth, and no path to `.done` anywhere in that function.

The developer, 2026-09-16, looking at a finished card still sitting in In progress: *"it should be
moved to done if the task has been completed."*

The observed case: `arch-1` in a repo with no remote was finished and committed (`99564f1`), its card
was hand-marked `status: done`, and the board went on showing In progress from a stage a stopped run
had left behind. Clearing the stage moved it to **Backlog** — the `case nil` — which is worse than
wrong, because Backlog is where unstarted work lives. Finished local work had nowhere to go, and the
only honest reading of the board was that the work had never begun.

`LocalBacklog.parse` already read every front-matter key into `fields`. `status` was parsed and then
dropped on the floor when the `BacklogItem` was built: the fact was in the repository the whole time
and the model had no field to put it in.

## Decision

**A `docs/backlog/` card's Done comes from the card's own file, not from `board.json`.**
`BacklogItem` gains `status` and `resolved`; `status: done` (matched case-insensitively) puts the
card in Done, and `resolved:` — free text, `2026-09-15 · 99564f1` — becomes the card's branch line,
since a local card has no branch to name there.

This does not reopen 0011's objection, and it does not weaken 0035:

- **It is not a second authority over git.** 0035 forbids stored state that *contradicts a fact*.
  Here there is no fact to contradict: no branch, no pull request, nothing for git to have said. This
  is the lifecycle git cannot see, which is the one thing 0035 says the app may record.
- **The file outranks a stored stage, and only for Done.** The check runs ahead of the stage switch,
  because a card left `inProgress` by an interrupted run is exactly the case this fixes — if the
  leftover stage won, the card would stay stuck for good. Every other column is unchanged.
- **Done stays unreachable for an issue card this way.** `status` is read only in `localTask`. An
  issue card's Done is still a merged pull request and nothing else.
- **A done card claims no diff it cannot show.** Changes and Evidence both read *"Finished outside
  the board — this card records the result, not a diff."*, and `isMerged` stays false: nothing was
  ever pushed.

## Rejected

- **A fourth `BoardStage` case in `board.json`.** It is machine-local bookkeeping: it does not travel
  with a clone, it is not reviewable, and it is discarded wholesale on a parse failure — the file is
  decoded all-or-nothing, so one bad value silently empties every card's stage. Recording that work
  is *finished* in a file with those properties loses the fact exactly when it matters most. The card
  is where the work is (ADR 0027), and it survives all three.
- **Deriving Done from the git history** — matching a commit that names the card. It guesses, and it
  reads as authoritative while guessing. A card is closed by a commit, by a decision, or by the work
  turning out to be unnecessary; only the last two have nothing to match, and they are not rarer.
- **Leaving it to the developer to delete finished cards.** Deletion is not completion: it destroys
  the record of what was done and why, which is the thing `docs/backlog/` exists to keep.

## Consequences

- `status:` is now meaningful front matter, not a comment. A card hand-marked `status: done` before
  this ADR — there is at least one — starts rendering as Done with no migration.
- `LocalBacklog.write` does not yet write `status:`; closing a card is still a hand edit of the file.
  **The UI move is deliberately deferred**: this ADR makes the state representable, and a Done button
  needs its own decision about what it writes into `resolved:`.
- An unknown `status:` value (`blocked`, say) is not a column and changes nothing. That is deliberate
  — a status vocabulary is a bigger decision than this one.
- `openTaskCount` already filters `.done`, so a finished local card stops counting as open and stops
  occupying an agent slot.
