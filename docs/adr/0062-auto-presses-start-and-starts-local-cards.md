# 0062 — Auto presses the card's own Start, and starts local cards

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit)

Amends [ADR 0018](0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md) — how Auto starts a task, and "tasks
without a number are Manual only".

## Context

On 2026-10-01 Auto was turned on for a project with no remote, whose Next up held twelve `docs/backlog/` cards
(ADR 0058). Nothing started: no session, no card moved. Two causes, either one enough:

- **`AutoScheduler` required `taskNumber`.** A local card has no issue and no `gh-N-` branch, so all twelve were
  dropped. 0018's "Manual only" for numberless tasks predates local cards, which are numberless by design.
- **Auto never used Start.** It opened an interactive agent in a terminal of its own (`terminals.startAgent`, 0018),
  while the card's Start became a `/dev` run with a remembered launch, the slot queue and the move to In progress
  (ADRs 0035, 0036, 0044). An Auto start would have bypassed all three and could not run a local card at all.

## Decision

- **Auto calls `model.startTask`**, the card's own Start, with the card's remembered launch when it has one and the
  project's agent otherwise. A card `startBlockedReason` refuses is skipped and not retried this session.
- **Local cards are eligible.** The base-ref requirement goes with the terminal path: where a run opens is Start's to
  resolve, as it is for a card started by hand.
- **Next up is walked in its hand order** (`nextUpOrder`), the order the board shows.
- **Starts not yet live hold their slot** for up to 60 s, the ledger `StartQueueRunner` already keeps.
- **The Auto switch is also on the board's header**, sharing one view with Settings › Project overrides.

## Rejected

- **Giving local cards a synthetic number.** Every other reader of `taskNumber` would then believe an issue exists.
- **Keeping the terminal path for numbered cards.** Two ways to start one card is how they diverged in the first place.

## Consequences

- An Auto start is indistinguishable from a click on Start: it appears in Sessions and moves the card to In progress.
- A card already worked on by hand (a branch, a worktree) and still in Next up is resumed by Auto, as Start would.
