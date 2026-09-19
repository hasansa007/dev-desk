# 0046 — One task model in three views: Board, Plan and Findings, one filter bar; Findings keeps its name

Status:  Accepted
Date:    2026-09-19
Commit:  (this commit)
Amends:  ADR 0035 — Queued stays a stored stage but is no longer a column; ADR 0038 — the survey list is
grouped by what each finding needs from you. Renames the Roadmap screen to Plan.

## Context

Reviewing Dev Desk on a real project (studyhub-deploy, 48 open issues, 9 milestones) the developer said the
board, the roadmap and the findings were *"kind of confusing"* and asked for *"a better UI, and better tasks
flow, organized and filtered view"*. What the screens showed on 2026-09-19:

- **Board:** two planned columns that disagreed — *Ready for dev 11*, *Queued 0*. Ready for dev already meant
  "the active milestone, plus moves made here" and Queued "waiting for an agent slot" (ADR 0035), but nothing
  on screen said either. No filters, only search. Most cards carried `impact —` and `complexity —`.
- **Roadmap:** ten milestone columns, three visible, scrolled sideways; no progress, no priority ordering
  (a P3 above a P1); `Committed` on every card. Which milestone fed the board was "the oldest, unless one has
  a due date" — true, and invisible.
- **Findings:** *Findings 35* in the sidebar, *14 findings* in the header, and all 14 "New · not filed yet"
  although ten were filed as #810–#819 — Dev Desk never read the report's `## FILED` table (fixed in
  `ef010c9`). A merged finding and two drift items rendered as raw report lines.

A working mock was reviewed and approved in direction: *"UI looks much nicer"*.

## Decision

**One set of tasks — the tracker's issues, or `docs/backlog/` without one (ADR 0027) — seen three ways, each
answering one question, with one filter bar.**

| View | Question | Shape |
|---|---|---|
| **Board** | what is moving? | Backlog · **Next up** · In progress · Review · Done |
| **Plan** (was Roadmap) | in what order? | one row per milestone, top to bottom |
| **Findings** | what did a hunt find that waits on me? | grouped by what each finding needs |

1. **Next up replaces Ready for dev, and absorbs Queued.** Next up = the working milestone's open issues plus
   cards moved there by hand, sorted by priority. A card waiting for an agent slot stays in Next up with a
   *waiting for a slot* pill: Queued is still the stage ADR 0035 stores, it is just not a column — an empty
   column that means "the queue is idle" read as "nothing is planned".
   **A P0 is always in Next up, whatever its milestone** — pinned first, marked *P0 · outside this milestone*.
   Plan's order ranks milestones and the label ranks inside one; without this a P0 in a lower milestone (or in
   none — #648 on 2026-09-19) waited behind the working milestone's P2s.
   **A card shows what it depends on, and a card that waits cannot start.** *part of #E* when it is a
   sub-issue of an open parent; *waits for #N* when its body records `needs: #N` / `blocked by #N` (the
   findings door's `needs:` line, carried into `## Scope`) and #N is open. Start is disabled on a waiting card,
   the reason on hover. This is how a bug and the refactor that rewrites its code stay ordered: either the bug
   is a piece of the refactor (sub-issue, fixed by it), or it ships first alone and the refactor `needs:` it.
2. **One filter bar on Board and Plan**: milestone, priority (P0–P3), type (bug/feature/epic), tag
   (security/payments), search. A filter set on one view holds on the other.
3. **Cards show only what is set.** Priority first, then security/payments, then the milestone. No
   `impact —` / `complexity —` placeholders; no chip that repeats on every card.
4. **Plan is a list, not columns.** Each milestone row shows done-of-total, a P0–P3 count, and its reason; it
   expands to its issues sorted by priority. The top row is marked **Working now** and is what Next up reads.
   **Move to top** reorders, stored per project in `.devdesk/` (not in the repository — ordering is the
   developer's, not the codebase's). With no stored order, the old rule stands (nearest due date, then oldest)
   and the row says which rule chose it. A final **No milestone** row lists each unplaced issue with its reason.
5. **Findings groups by need**: *Needs your decision* (confirmed, not filed), *Not verified yet*, *Filed* (links
   `#N`), *Added to an open issue* (`Added to #N`), *Dropped*. The sidebar count is only what waits on you.
6. **The screen keeps the name Findings. Its action is "Hunt for issues"** (was "Run findings"): the action
   says what happens; the screen names what it holds. The door stays `dev:findings`, the folder
   `docs/findings/`.
7. **Settings gains a project section, "Board and plan"**: what Next up follows (Plan's order / nearest due
   date), how Next up is sorted, how many Done cards show, whether docs-only pull requests appear in Review.
   Sections are grouped by scope — *This Mac*, *This project*.
8. **Diagrams show where the open work is** — each part of a drawing carries a count of the open issues whose
   fix touches its files, and opens the Board filtered to them. **Deferred to its own step:** it needs a
   mapping from a drawing's nodes to the `touches:` of issues, which neither side records yet.

## Names considered for the Findings screen, and why each lost

| Name | Why not |
|---|---|
| Inbox | a mail metaphor — the developer: *"it's not a mail app"* |
| Triage | declined by the developer |
| Observations | Dev Desk already labels an unverified finding "Unconfirmed observation"; a confirmed defect would become one too. Also reads as observability (logs, metrics) |
| Signals | the developer's product vocabulary already uses "signal" for user traction (joins, builds, checkouts) |
| Leads | fine, but a new word for something the whole family already calls a finding |
| Proposals | the right name only if the screen becomes one queue for everything awaiting a yes/no — findings, ideation, roadmap themes. **Revisit if it does.** |
| Detections | security-tool vocabulary for automatic, often false-positive alerts — undersells findings that two refuting checkers confirmed, and suggests security only |

**Findings** stays: neutral, the door's own word, and zero migration. The confusion was the screen's grouping
and a filing status it could not read — not its name.

## Alternatives rejected

- **Keep Queued as a column.** Its only honest content is a transient agent-slot queue; empty, it reads as
  "nothing planned" next to a full Ready for dev.
- **Roadmap as columns, fixed.** Nine milestones do not fit side by side on any screen; order and progress are
  the questions a plan answers, and a list answers both.
- **Store the milestone order as GitHub due dates.** Writes invented dates into the tracker to express a
  preference; `.devdesk/` holds per-developer state already (ADR 0035's board.json).
- **A separate Issues list view.** Raised and not taken now: Board with filters covers "find one issue"; revisit
  if search inside the Board proves too narrow.

## Build order

1. Findings: the action named "Hunt for issues"; grouping by need.
2. Board: Next up (Ready for dev renamed, Queued folded in as a pill); the shared filter bar; quieter cards.
3. Plan: the list, Working now, Move to top stored in `.devdesk/`, the No milestone row.
4. Settings: *Board and plan*, scope grouping.
5. Diagrams: open-issue counts per part (deferred — needs node → touches mapping).

## Consequences

- One vocabulary across views: Next up is the Plan's top row, and the Plan's top row is where Next up comes from.
- A reorder in Plan changes the Board immediately and touches nothing on GitHub.
- Findings never compete with Plan for priority: a finding has none until it is filed, and filing is where it
  gets a label and a milestone. Ranking lives in one place.
- The kanban door's QUEUE (`dev:kanban`) still reads the active milestone by due date; it learns `.devdesk/`'s
  order in the same step as Plan, or the two disagree.
