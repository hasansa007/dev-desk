# 0049 — A ticket fans out into slices under an orchestrator, and its decisions are front-loaded

Status:  Accepted — design; no code yet
Date:    2026-09-20
Commit:  (this commit)

Extends the read-only fan-outs of Phases 2, 6 and 13 to the implement phase, and narrows
`00-principles.md`'s *"Automatic never means unattended"* by naming the one place the four gates may
be collapsed into one.

## Context

`/dev` already runs master/worker three times, and every worker is read-only: 2–3
`feature-dev:code-explorer` at Phase 2, 2–3 `feature-dev:code-architect` at Phase 6, a verified
reviewer fan-out at Phase 13. Writing is single-threaded — Phase 9 reaches for
`subagent-driven-development` only "for complex tasks (3+ files touched)".

Parallel writing exists only *across* tickets: `dev:findings` files `group:` / `needs:` / `shares:`,
Phase 3 routes each to its own base, and Dev Desk runs them as separate sessions over
`AgentProtocol`. Nothing parallelises the inside of one ticket.

The developer, 2026-09-20: *"make claude be the master and other agent are slaves … Claude triggers
as much agenents needed as possible — then track or watch helps them if he can — review their work
then notify human (user) on finish"*.

Four things stand in the way of the literal reading, and they shape the decision:

- **One checkout, N writers corrupts the tree.** The existing fan-outs are safe because nobody edits.
- **The ceiling is the dependency graph.** Phase 8 orders tasks *by dependency*; a typical ticket has
  one to three independent leaves. Six agents on a chain of six is slower than one.
- **Review does not parallelise.** The orchestrator never saw the code, so reviewing it means reading
  every diff — Phase 13's cost, back on one agent.
- **A dispatched agent cannot be steered mid-turn.** "Watch and help them" is not available; only
  what they report when they stop.

And *"notify human on finish"* collides with Phases 5, 6, 14 and 16, which stop because a decision is
the developer's, not because a step ended.

## Decision

- **A ticket may fan out at Phase 9, and only at Deep tier.** Light tier already forbids subagent
  reviews; it forbids subagent *writers* too. Standard fans out only when the developer asks.
- **Width is the number of independent leaves in the Phase 8 graph**, capped by `--max-agents=<n>`,
  which is already the pre-approval (ADR 0043). A plan needing more than the cap refuses and spends
  nothing.
- **One worktree and one branch per slice.** A slice is a `group: G<n> · i of m` unit with the Phase 3
  base rules — no second parallelism model. The group branch **merges** its base in, never rebases.
- **Contract-first dispatch.** The orchestrator writes each slice's acceptance criteria and its
  failing test *before* dispatch. A slice is reviewed against its contract, never against intent.
- **The writer is never the reviewer**, as at Phase 13.
- **Two strikes, then surface.** A slice that fails its contract twice returns as a finding for the
  developer, not a third attempt. Cheap failure replaces the supervision that is not available.
- **Watching is checkpoints, not observation.** Each slice checkpoints per phase (ADR 0044); the board
  is the progress view. The orchestrator reports; it does not supervise.
- **The decisions are front-loaded into one pack.** Phases 5 and 6 are answered together, once, before
  any slice starts: the clarifications, the architecture pick, and the slice plan with its agent count
  and bill. The run is then unattended to Phase 13 and stops at 14 as it always did. Phases 14 and 16
  are untouched.

## Rejected

- **"As many agents as possible."** Width tracks the dependency graph, not the budget; agents beyond
  the independent leaves queue behind each other and pay orchestration on top.
- **N writers in one checkout**, coordinated by file ownership. One agent reading a file mid-write by
  another is a class of bug with no test, and the orchestrator cannot see it happen.
- **A supervisor that watches and intervenes.** A subagent cannot be steered mid-turn; a supervisor
  would poll transcripts and guess. Checkpoints and two strikes give the same recovery honestly.
- **Making every tier fan out.** A slow pipeline that gets skipped protects nothing
  (`00-principles.md`), and most tickets have one leaf.
- **Dropping the four gates so the run reaches "done" alone.** Front-loading moves 5 and 6 earlier and
  merges them; 14 and 16 are the prod decisions and stay where they are.
- **A new orchestration vocabulary.** `group:` / `needs:` / `shares:` already carry base and landing
  order for parallel agents; a second scheme would have to be kept in sync with it.
