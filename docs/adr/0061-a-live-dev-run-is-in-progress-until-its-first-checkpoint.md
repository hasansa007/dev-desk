# 0061 — A live `/dev` run is In progress until its first checkpoint, and Start names the checkpoint command

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit)

Amends [ADR 0044](0044-a-card-moves-on-its-runs-checkpoints-not-on-a-terminal.md) — "Start moves nothing".

## Context

0044 moves a card only on a checkpoint (`.dev/issue-N.json`, `.dev/local-ID.json`) or a commit, and relies on
`/dev` writing one after every phase that clears — a rule in `shared/pipeline/00-principles.md`. On 2026-10-01 a
run started on a CallApp local card read that rule, cleared phases 1–3, and was reproducing the bug on a
simulator in Phase 4 without ever running the command. Its card sat in Next up, marked Running, the whole time.
The developer, from the screenshot: *"task is running but stuck in next up instead of in progress"*.

So the column depended on one agent remembering one line, and a forgotten line looked like a board bug.

## Decision

Both of these:

- **Start names the command.** The prompt's arguments end with *"After each phase that clears, run: python3
  ~/<root>/scripts/dev.py state checkpoint --phase <N> --issue N"* (or `--local <entry id>`), keyed to that card,
  so the run no longer derives the key from the rule. The prompt keeps `build_prompt`'s shape — one more
  argument, not a new sentence.
- **The run Start launched is In progress while it is live.** `ProjectWindowModel.workColumn`: a card in
  Backlog, Next up or Queued whose `/dev` run is live is drawn, and counted, in In progress. When the run ends
  with no checkpoint and no commit, the card goes back. A checkpoint or a commit then holds it there as 0044
  says, and nothing already in Review or Done moves.
- **A shell or a hand-opened agent still moves nothing.** That was 0044's complaint, and it stands: only the
  door run, which is the work, counts.

## Alternatives rejected

- **Only the prompt.** Still depends on the agent; this is the failure that happened.
- **Only the live run.** Loses the phase note (*Planning · phase 4 done*), which comes from checkpoints alone.
- **The app writes a checkpoint at Start.** It would claim a phase nothing cleared, and outlive a run that died,
  which is exactly the stale `inProgress` 0044 removed.

## Consequences

- The stored stage in `.devdesk/board.json` is unchanged by a live run; the move is drawn, not recorded.
- `dev run` in the CLI builds its own prompt and does not name the command yet.
