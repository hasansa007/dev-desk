# 0060 — A local card waits for what it needs, and Next up puts it after them

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit)

Extends [ADR 0046](0046-one-task-model-three-views-findings-keeps-its-name.md) decision 1 ("a card that waits cannot
start") from issues to `docs/backlog/` cards. Extends [ADR 0027](0027-work-without-a-tracker-is-recorded-locally-and-promoted-on-request.md):
the header the app reads gains `needs:`, and promotion rewrites it.

## Context

Decision 1 reads `needs: #N` / `blocked by #N` from an issue's body, shows *Waits for #N* and disables Start
while #N is open. A local card has no issue number for anything to need. `dev:findings` writes its order between
local cards as keys of other entries instead: `needs: 2026-10-01-C9, 2026-10-01-C11`, or `needs: none`.
`LocalBacklog.parse` dropped the line, so every local card could start.

Found 2026-10-01 in a repository with no remote: twelve cards from one findings run, C5 needing C9 needing C3.
Start was enabled on all of them, and starting them all would have run C5 before the C9 it is built on.

## Decision

**A local card's `needs:` holds Start the way an issue's does, and orders Next up.**

- **Read:** `needs:` is comma-separated refs, kept as written: a key of another entry, or `#N` for an issue.
  `none` (and `-`, `null`) is no ref.
- **Resolved:** a key naming an open entry waits on that card. One naming an entry that became an issue, still
  in `docs/backlog/` or already in `filed/`, waits on the issue. A key that names nothing is shown in the card's
  dependencies and not waited on, the same as `needs: #N` for an issue that is not open.
- **Waits:** the card says *Waits for &lt;key&gt;* (or *#N*) while the blocker is on the board and not Done, and
  Start is disabled with the reason on hover. A local blocker is done when its card says `status: done`, the
  only Done a local card has (ADR 0035 amendment); an issue is done when it is no longer open. The card it blocks
  is listed on the blocker as *Blocks &lt;key&gt;*.
- **Ordered:** in Next up and Not started, local cards come after the local cards they need (topological), then
  by priority, then in the builder's order (the run's `order:`, then file name). A card that unblocks another
  ranks at that card's priority when it is higher. A cycle is placed by priority alone.
- **Promoted:** when an entry is filed as #N, the entries still waiting on its key have it replaced by `#N` in
  their `needs:` line. File on GitHub asks the door to keep the line in the issue's Scope, so an issue whose
  needs were filed first reads `needs: #N` and decision 1 enforces it. A key whose entry is not filed yet stays
  a key.
- **Issues are unchanged.** The same reason text, the same `#N` rule; only edges between local cards reorder a
  column.

## Alternatives rejected

- **Priority first, dependencies as a tie-break.** It is the sort the report showed failing: C5 is the P1 and
  would lead the column it cannot start in.
- **Plain topological order with each card's own priority.** Simpler, and it puts every unrelated P2 between a P1
  and the P3 that unblocks it. Raising a prerequisite to what it unblocks keeps the P1's chain together.
- **Rewrite the needs of an issue already filed when its blocker is filed later.** It means the app editing a
  GitHub issue's body, which no part of it does and promotion is the door's run (ADR 0027). Filing in dependency
  order, which Next up now gives, avoids the case.

## Consequences

- A findings run's chain is enforced with no tracker and no `.devdesk/board.json`.
- An issue filed before what it needs keeps the key in its `needs:` line, which decision 1 does not read. The
  issue still names its prerequisite; enforcing it is a by-hand `needs: #N`.
- Start All skips a waiting local card, since it filters on the same reason.
