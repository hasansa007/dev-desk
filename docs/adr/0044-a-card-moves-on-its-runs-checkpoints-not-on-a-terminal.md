# 0044 — A card moves on its run's checkpoints, not on a terminal opening

Status:  Accepted
Date:    2026-09-17
Commit:  (this commit)

Reverses ADR 0035's *"a start is the move to In progress"* and the live-session promotion out of the
unstarted columns. The rest of 0035 (Ready for dev and Queued as stored stages) stands.

## Context

A Start wrote `inProgress` to `.devdesk/board.json`, and any live shell promoted its card too, so a card sat
in In progress whether or not anything had been done. `/dev` never called `dev.py state checkpoint`, so the
phase note the board can show was always empty. The developer, 2026-09-17: *"make the board task state be
updated running or done or any other state not if opened terminal or terminal related but code and
accomplishments"*, and *"close terminal once done"*.

A branch-keyed checkpoint had nowhere to live: a feature's branch is cut after Phase 5, and a Dev Desk task
run starts on a detached worktree.

## Decision

- **`/dev` checkpoints every phase that clears** (`00-principles.md`), keyed by the task:
  `.dev/issue-N.json` (`--issue`) or `.dev/local-ID.json` (`--local`).
- **The board reads those files from every worktree.** A checkpoint puts the card in In progress with
  *"Planning · phase 4 done"*; git still decides In progress by commits, Review and Done.
- **Start moves nothing.** It takes a card out of Queued into Ready for dev; a leftover stored `inProgress`
  reads as Ready for dev. The card still shows that it is running.
- **A Done task's session is ended and taken off the list** — for Claude, once its turn has ended
  (a `UserPromptSubmit` hook marks a turn begun), so a closing report is not cut off.

## Rejected

- **Git only** — phases 1–8 (investigation, discussion, plan) would never show.
- **New Planning and Verifying columns** — the developer kept the columns and put the phase on the card.
