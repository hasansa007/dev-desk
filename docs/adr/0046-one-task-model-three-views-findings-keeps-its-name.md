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
7. **Settings gains a project section, "Work"** (`.devdesk/work.json`): what Next up follows (the top of the Plan /
   the nearest due date — `dev.py board` reads the same choice), how many Done cards show before "N more", and
   whether pull requests with no issue behind them (a report, a docs edit) appear in Review. Sections are grouped
   by scope — *This Mac*, *This project* — and the list sits on the navigation colour. *Dropped at build time:*
   "how Next up is sorted" — priority order is what decision 1 rests on, and a second ordering is only a way to
   bury a P0.
8. **Diagrams show where the open work is** — each part of a drawing carries a count of the open issues whose
   fix touches its files, and opens the Board filtered to them. **Deferred to its own step:** it needs a
   mapping from a drawing's nodes to the `touches:` of issues, which neither side records yet.

9. **The sidebar follows the flow**: *Findings, Ideation* (decide) · *Plan* (order) · *Board, Sessions* (do) ·
   *Diagrams* (see). It listed Board, Sessions, Plan, Findings — nearly backwards, so the path from a finding to
   a started task read right to left. Board stays the view a project opens on; the `⌘` numbers follow the order.
10. **Filing is called File.** A Findings row's action was labelled *Backlog*, but a filed finding lands in Next
    up when its milestone is being worked or it is a P0 — the label named a destination it often did not reach.
    It names the action, matching the *Filed* section it moves to and Add Task's wording.
11. **Start checks for code another running task is changing.** An issue's `touches:` (the findings door's line,
    carried into `## Scope`) is compared with every task In progress — its own `touches:` and its branch's changed
    files. *Same function*: Start asks — **Queue after #N** (records a local wait, `.devdesk/waits.json`, which the
    Waits-for rule then enforces) or **Start anyway**. *Same file, different functions*: a note, no question — git
    merges different code cleanly. Priority is never a block: Next up already ranks, the developer decides.
12. **Every screen says where it sits in the flow.** Each sidebar item has a one-line tooltip, and each screen an
    ⓘ that explains what it holds, what you do there, and what comes before and after — so a first-time user can
    find their way from a finding to a merged fix without a manual.

13. **Plan and Board are one tab, Work: milestones on the left, their Board on the right** (option B of three
    mocked 2026-09-19 — a Plan|Board switch, this split, and milestone swimlanes — chosen by the developer). They
    were two tabs showing the same issues grouped two ways, which read as two different things. The list keeps
    Plan's order, progress, P-counts and Move to top; selecting a milestone narrows the Board to its issues;
    **All milestones** (first row) is the whole Board, P0s pinned as in decision 1. Its three costs, answered:
    the list collapses to a rail so a 13″ screen gets the Board's width back; each row shows its P0 count and a
    narrowed Next up says *N P0 in other milestones — show all*; and the default selection is the Working now
    milestone. The sidebar becomes Findings, **Work**, Sessions — the daily flow — then Ideation, Diagrams, the
    occasional tools (Ideation moved out of second place on 2026-09-19: it read as a step every task passes
    through). The stored `roadmap` value opens Work. This supersedes decision 4's separate Plan screen; its list lives on as Work's left pane.
    *Rejected:* the switch (order and stage never on screen together); swimlanes (mostly empty cells, Backlog and
    Next up stop existing as words, the largest rebuild).
14. **Every tab has one header, drawn by one component** (`ScreenHeader`, mocked and approved 2026-09-19). Row one,
    48 pt: the title and its ⓘ, one muted status line (counts, and the run or milestone on screen), then tools, then
    at most one primary button, always last — Hunt for issues, New task, New session, Generate ideas, Regenerate.
    Row two, 36 pt, only when a tab has its own controls (`ScreenBar`): Findings' kind and grouping, Work's filters,
    the session tabs, Ideation's verdicts. The header spans the tab; an inner list (milestones, diagram kinds,
    ideas) starts below it and has no title of its own. Before, the title sat in five places: pushed right by
    Work's milestones, inside Ideation's and Diagrams' lists, and absent from Sessions. The header also shows before
    the first run, so an empty tab has the same title and button. Sessions' "+" went, since New session is the same action.
    Findings' "what this report could not check" button uses an eye-slash icon, so the header has only one ⓘ.
    *Not applied:* Settings. It is a dialog with its own title bar, and a tab header inside it only repeated
    "Settings".
15. **One chip in every second row** (`FilterChip`, mocked and approved 2026-09-19). Four controls did one job
    there: Findings' segmented control plus its own Ignored chip, Work's small black chips, Ideation's blue square
    chips. Now: 28 pt, 13 pt text, the count in grey inside, light blue when on (black was the heaviest thing on
    screen and used nowhere else), a grey label before each group, a hairline between groups. **Pick-one** groups
    always have one chip on (Findings' Show and Group, Diagrams' Draw); **filter** groups may have none and show
    Clear while any is on (Work, Ideation). The row scrolls sideways on a narrow window rather than squeezing a
    chip; its trailing group stays pinned right. Diagrams' Sequence picks its flow from a menu in the same row,
    not a list on the left, so every kind draws full width (ADR 0047 decision 4 amended). The header's
    button on Diagrams is Redraw, to match Draw.
16. **Work's filters live in its left list, not a row** (option C of four mocked 2026-09-19 — three lines, a
    popover, this, and a fold-away row — chosen by the developer). The list is everything that narrows the Board:
    Milestones, with a stage switch (All · Open · Working now; Open, the default, folds finished milestones into
    "Show N finished"), then Priority, Type and Tag as checkboxes. Each section folds, remembered; its header says
    "1 on" in blue while it filters. Counts take the other groups into account and 0 is dimmed. Filters never
    hide: the header reads "P1, Bug · 3 of 11 shown", Clear all (n) heads the list, and the collapsed rail
    carries the count. The milestone list itself is never filtered — the selected one cannot vanish. A Hide Done
    switch sits above the columns. Work is the one tab with no chip row: its list does that job. Run roadmap
    sits in the Milestones section header, with the collapse button, since it is what creates milestones.
17. **Small ⓘs where a part needs one, not one ⓘ for everything.** Work's header ⓘ had grown to six paragraphs
    covering the list, the Board and the filters. It now covers the Board only; Milestones has its own ⓘ
    (Working now, Move to top, stages, and what Run roadmap does). Priority, Type and Tag get no ⓘ — they
    explain themselves — only a tooltip on the section header saying what the counts mean.
18. **One filter panel on every tab that narrows its view** (`FilterPanel`, mocked 2026-09-19 and chosen over a
    chip row under the header). Left of the content, its own header the same 48 pt as the tab's: title, ⓘ,
    collapse. Inside, groups of the same `FilterChip`, wrapping; each group can show as chips (the default) or as
    a menu, remembered per group. Pick-one groups keep one on; filter groups show counts that take the other
    groups into account, dim their zeros, and are cleared by Clear all. Collapsed, the panel is a thin strip with
    the count of filters on. Work: Milestone (a filter group like Tag — none on is every milestone, Now marks
    Working now, right-click Make Working now, Run roadmap on the group; names cut at the dash, full on hover),
    Priority, Type, Tag. Findings: Run, Show, Group by. Diagrams: Draw, and Flow on Sequence with "Draw another
    flow…". Ideation: Run, Verdict. Sessions has nothing to narrow and keeps its tab row. This supersedes the
    chip row of decision 15 and the milestone list and stage switch of decisions 13 and 16: the milestone rows
    no longer repeat counts and progress the Board and the header already show.

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
6. Sidebar order, File, the Start overlap check, and the per-screen tooltips and ⓘ (decisions 9–12).
7. Work: Plan and Board in one tab, milestones left, Board right (decision 13).

## Consequences

- One vocabulary across views: Next up is the Plan's top row, and the Plan's top row is where Next up comes from.
- A reorder in Plan changes the Board immediately and touches nothing on GitHub.
- Findings never compete with Plan for priority: a finding has none until it is filed, and filing is where it
  gets a label and a milestone. Ranking lives in one place.
- The kanban door's QUEUE (`dev:kanban`) still reads the active milestone by due date; it learns `.devdesk/`'s
  order in the same step as Plan, or the two disagree.
