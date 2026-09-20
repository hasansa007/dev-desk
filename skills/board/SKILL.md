---
name: board
description: >
  The BOARD — what you are on, what is queued, what is next, and the shape of the backlog, in one
  screen, plus the bounded writes that move a card. Reads the repo's GitHub issues once and
  classifies them into columns derived from git: QUEUE (the active milestone), IN FLIGHT (a branch
  with unmerged commits), PR OPEN, HUMAN REVIEW, BACKLOG, plus DEFERRED (epic-leftover) and an
  ORPHANED warning row. Then reports the counts and asks which to start.
  Bare `/dev` offers it when the tracker has work (Entry 0). Replaces the earlier read-only `dev:issues`.
  Writes are BOUNDED, never free: move a card (labels, milestone) · cancel it (close as "not
  planned", reversible) · delete it (permanent, behind a hard gate). It still never cuts a branch
  and never starts work — naming an issue hands off to `/dev #N`.
  Trigger on: "what should I work on", "what's next", "show the issues", "show the board",
  "show the backlog", "tracker", "board", "issue stats", "what's in flight", "how many open
  issues", "what am I working on", "queue this", "move this card", "cancel that issue".
allowed-tools: [gh, git]
---

# board — the board, and the few writes that move a card

A **tool**, not a phase. It answers *"what should I work on?"* and hands off. **It never cuts a
branch and never starts work** — that is `/dev #N`. It never *files* an issue either — that is
`/dev:create-*`.

What it may do that its predecessor could not: **move, cancel and delete cards**, under Phase 7's
guards.

> **Replaces `dev:issues`.** Everything below marked *verbatim* is carried over unchanged, scars
> included. The one clause that could not survive is named in `## Never`.

## Phase 0 — Prefer the CLI, fall back to prose

If `~/.claude/.dev-root/scripts/dev.py` exists, Phases 3–5 are already implemented there:

```bash
python3 ~/.claude/.dev-root/scripts/dev.py board --json [--milestone "<active>"]
```

It returns the columns, the epic progress and the ordering, computed the same way every run. **If it
is absent, do Phases 3–5 by hand from the prose below** — the CLI is optional and this door must
work without it. Never report a number the CLI gave you as if you had checked it, and never skip a
rule below because you assume the CLI applied it.

Without `--milestone` the CLI resolves the active milestone by `dev:roadmap`'s rule — the top of Dev Desk's
Plan order (`.devdesk/plan.json`) first, then the nearest due date, then the oldest — and returns it
as `active_milestone`, with the reason in `active_why`. Pass the flag only to override that choice.

### Optional — mirror to a GitHub Project v2 board

If you want a draggable board on github.com, `dev project --number N` pushes the columns computed
here into that project's Status field.

**The project MIRRORS; it never decides.** Columns are computed from `git` and `gh` as always, then
written outward. Project status is **never read back as truth** — a stored value that can disagree
with git is precisely the class of bug 4.4's precedence rule exists to prevent, and a board is more
convincing than a state file because you can drag it.

Dry run by default. It refuses to invent a Status option that does not exist: an unmappable column
is reported, not guessed. Needs `gh auth refresh -s project`; without it the adapter says so and
everything else works unchanged.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | the board + the counts | this |
| `stats` | the counts only, no list | full view |
| `all` | include P3 and DEFERRED | top of each bucket |
| A label (`payments`, `P1`, `epic`) | filter to it | no filter |
| `move #N <label\|milestone>` | Phase 7 — a reversible edit | — |
| `cancel #N` | Phase 7 — close as *not planned* | — |
| `delete #N` | Phase 7 — permanent, hard gate | — |

## Phase 2 — Resolve the repo

Read `~/.claude/.dev-root/shared/entry.md` — repo auto-detect and pre-prod branch resolution. Both
are needed: the repo to query, the pre-prod branch to measure "unmerged" against. Do not restate
that logic.

**The resolved repo is a BOUNDARY, not a hint.** Render the board for that repo and no other. An
empty board *is* the answer when the tracker is empty — do not go looking for a fuller one
elsewhere. Another repo's backlog is a **sentence you may say**, never a board you render:
*"nothing here; the other checkout has 11 open — want that board instead?"* and then stop until
asked.

> **2026-08-05 — observed, in the predecessor's own first week.** Invoked from a repo whose tracker
> has never held an issue, it correctly reported zero — then offered to run against a different
> repo, did so, and rendered a board of that repo's issues and branches. The user's next message was
> *"what branch, what repo?"*, because two repos' state had been merged into one answer with
> nothing marking the seam.
>
> `dev:launch` 2.2 already carries this rule — *"A session can reach many repos; exactly one of them
> is `$PROJECT_ROOT`"* — and it was written after the same mistake in the same week. A board is more
> tempting to widen than a launch, because an empty board feels like a failure to be fixed. It is
> not: **an empty tracker is a finding, and a full board from the wrong repo is worse than nothing.**

**Writing widens the boundary's cost.** Phase 7 edits real issues, so state `owner/repo` out loud
before any write, every time. `shared/entry.md`: *"Authorization to fix something is not
authorization to fix it anywhere."*

## Phase 3 — Fetch once

```bash
gh issue list --state open --limit 200 \
  --json number,title,labels,updatedAt,milestone,body
```

**One call, not one per issue.** `gh issue view` per row turns a 15-issue tracker into 15 round
trips for data the list already returned — `body` included, which is what makes 4.1's epic parse
possible from the single fetch. Fetch closed **counts** separately and only for stats:
`gh issue list --state closed --limit 500 --json number -q 'length'`.

If the repo has no issues or `gh` is not authenticated, say so plainly and stop — **an empty board
and a failed query must never render the same.**

## Phase 4 — Classify

Columns, in this order. An issue lands in the first that matches.

| Column | Test | Authority |
|---|---|---|
| **DEFERRED** | labelled `epic-leftover` — parked deliberately, not forgotten | label |
| **HUMAN REVIEW** | an open PR whose `reviewDecision` is set | `gh` |
| **PR OPEN** | an open PR with no review yet | `gh` |
| **IN FLIGHT** | a branch exists for it **and** carries commits not in the pre-prod branch | git |
| **QUEUE** | a member of the **active milestone** | `gh` |
| **BACKLOG** | everything else that is **startable** (see 4.1) | — |

**CURRENT is a marker, not a column.** The issue your branch maps to is flagged wherever it sits —
a card can be IN FLIGHT *and* current.

**ORPHANED is an anomaly row, not a column** — see 4.3.

### 4.1 — An epic parent is not startable

An issue labelled `epic` **with open children is never offered as startable.** Offer its first
unstarted child instead, and show the parent only as progress (`#E <epic title> 0/4`).

This is the family's own rule, not a preference — `README.md`: *"split it at Phase 5 into real
sub-issues, run `/dev #child` per slice — the sub-issue list IS the queue."* Starting `/dev #E`
would re-enter decomposition on an epic that is already decomposed.

**Parse the TASK LIST, never a bare `#N` grep.** Children are the checklist lines; anything else is
prose:

```bash
gh issue view <epic> --json body -q .body \
  | grep -E '^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*#[0-9]+'
```

> **2026-08-05 — a bare grep invented a child.** An epic's body referenced an unrelated roadmap
> issue twice in **prose** (*"see the Roadmap issue #R"*, *"Roadmap context: #R"*) while its actual
> children were four `- [ ] #N` checklist lines. Grepping `#[0-9]+` returns five children — the
> roadmap issue among them, and it is closed — and so reports the epic as **1/5 done**. The truth
> is **0/4**, nothing started. An epic whose progress bar is wrong is worse than one with no
> progress bar, because it is the number you would plan from. Epics cross-reference roadmaps,
> superseded issues and spin-offs constantly; only the checklist is a parent-child claim.

`scripts/dev.py` encodes this as `parse_epic_children`, with that exact body shape as a fixture.

Count progress over **all** children, open and closed — an epic that is `3/4` done reads nothing
like `1 open`. That needs each child's state, which the open-only fetch in Phase 3 does not have,
so query the children explicitly.

An `epic` label with **no** open children is just an issue — treat it as startable.

### 4.2 — "Unmerged" needs the right base

A branch is only IN FLIGHT if `git rev-list --count <pre-prod>..<branch>` is non-zero. Measuring
against `main` in a two-stage repo marks everything already merged to pre prod as still in flight —
a board that reports finished work as unfinished is worse than no board.

Local branches accumulate: a real repo carried branches for long-since-merged issues, dozens of
them. **A branch existing proves nothing; only unmerged commits do.**

### 4.3 — Unmerged work on a CLOSED issue is the finding, not a filter miss

A board built only from `--state open` cannot see this, and it is the state most worth seeing.

> **2026-08-05, on the first run against a real tracker.** Two branches carried **5** and **2**
> unmerged commits — and both of their issues were **CLOSED**. So either the issues were closed
> while work was still outstanding, or the branches are abandoned and should be deleted. Both
> readings need a human; neither is visible from the open list. By contrast a third branch of
> similar age had 0 unmerged commits — genuinely stale, and correctly silent.

Report ORPHANED as **one warning line, never as work to start**, and say which of the two readings
it is only if you can tell. **Do not delete branches here** — Phase 7's writes are on issues, not
on refs.

### 4.4 — The phase column is ADVISORY

When `.dev/<branch>.json` or `.dev/issue-N.json` exists, a card may also show `planning` · `coding` · `validation`.

> **Git is authoritative; phase state is advisory.** Every column above is recomputed from `git` and
> `gh` and cannot be stale. The phase comes from a file that *can* lie. Where they disagree, **git
> wins and the row says the state file disagreed** — never the reverse.

No state file means **no phase claim at all**. Blank is honest; a guess is not.

## Phase 5 — Order BACKLOG

1. **Priority label** — `P1` → `P2` → `P3`. Unlabelled sorts *after* `P3`: unprioritised is not
   urgent, and silently promoting it would make the label meaningless.
2. **Slice order within an epic** — `Slice 1` before `Slice 2`. Never offer slice N+1 while slice N
   is open; the numbering is a dependency statement.
3. **Oldest `updatedAt` first** inside a tie — the thing that has been ignored longest.

Show the top 2–3 of BACKLOG by default, not all 15. A board you have to scroll is a board you skip.

## Phase 6 — Render, then ask

```
## <repo> — 15 open / 135 closed

CURRENT   none — on `<pre-prod>`, clean tree

QUEUE     #A   P1  <title>                        [milestone: <active>]
IN FLIGHT #B   P1  <title>                        [coding · advisory]
PR OPEN   #C   P2  <title>

BACKLOG   #D   P2  <title of the oldest untouched P2>
          #E   P3  <title>

P1 2 · P2 5 · P3 8 · unlabelled 0
epics 2   #E <epic> 0/4 slices · #F <epic, no children — startable>
deferred  4 epic-leftover        (show with `all`)

ORPHANED  <branch-1>  5 commits, its issue CLOSED
          <branch-2>  2 commits, its issue CLOSED

→ start #A, queue another, or name a card to move?
```

**End by asking, never by listing.** The board exists to produce a decision; stopping at the list
leaves the user to re-type a number you already know. Naming one hands to `/dev #N` — this skill
does not start it.

## Phase 6b — When BACKLOG is empty, read what the repo says about ITSELF

Fires only when BACKLOG has nothing — an empty tracker, or every issue classified elsewhere.
"Nothing to start" is a true answer and a useless one; a repo that tracks no issues still knows
where it is weak, because it wrote it down.

**Read only what is already written. Never invent work.**

| Source | Find it with |
|---|---|
| Self-declared gap sections | `grep -rnE "^## (Known gaps\|Known limits)" --include="*.md"` |
| The family's honesty convention | `grep -rn "Undated, therefore unproven" --include="*.md"` |
| Deferred work in a spec's status line | `grep -rniE "^\*\*Status.*(deferred\|NOT (implemented\|executed))"` |

Render them grouped by source file, and **label them as the repo's words, not yours**. The
distinction is the whole point: a gap the repo recorded is evidence, and a gap you thought of on
the spot is a guess wearing the same clothes.

**If the repo declares no gaps, say so and just ask.** *"This repo records no gaps"* is an honest
answer. Manufacturing a backlog to fill the space is the failure this phase exists to avoid — an
invented board is worse than an empty one, because an empty one is obviously empty.

**One ranking judgement is allowed, marked as yours:** which recorded gap costs most if it bites.
Say why in a clause — *"the only one here that loses data"* — so it reads as a claim that can be
argued with, not a priority handed down.

Then ask what they want to work on. That question is the point of the phase; the gap list only
exists so the question is not asked into a vacuum.

## Phase 7 — Act: the bounded write set

Three tiers. **State `owner/repo#N` out loud before every one.**

| Tier | Command | Reversible | Guard |
|---|---|---|---|
| **Move** | `gh issue edit <N> --add-label / --milestone` | yes, trivially | none beyond the run |
| **Cancel** | `gh issue close <N> --reason "not planned"` + a comment saying why | yes — `gh issue reopen` | confirm once |
| **Delete** | `gh issue delete <N>` | **NO** | 7.2 |

**Queueing is a move.** Adding an issue to the active milestone is what "convert this to a task"
means here. A chosen queue order **overrides Phase 5** — Phase 5 ranks what *could* be next; the
queue records what was *decided*, and a decided order is never silently re-sorted by priority label.

**Cancel always writes the reason as a comment**, not just the state. A closed issue with no reason
is indistinguishable from one closed by accident, and `dev:roadmap` reads these back so a declined
direction is not re-proposed next quarter.

### 7.1 — An epic's children come first

Before cancelling or deleting anything labelled `epic`, enumerate its children (4.1's parse) and
present them. Then pick one, explicitly:

- **cascade** — close the children too
- **re-parent** — move them under another epic, or to standalone
- **orphan-and-report** — leave them, and say so loudly

Never let children fall silently into DEFERRED. That column means *epic-leftover*, and it would
absorb them without a trace.

### 7.2 — Delete's hard gate

`gh issue delete` is permanent. There is no restore API. Two things make it worse here than
"irreversible":

- **Phase 14 writes `Closes #N` into merged PR bodies.** Delete the issue and that reference dangles
  in git history forever, pointing at nothing.
- **Epics have children**, and 7.1 exists because of it.

So:

1. Print `owner/repo#N` and its title, and require confirmation **against that**, not a bare yes.
2. **REFUSE outright** — not ask, refuse — when a merged PR references the issue, or when it has
   open children that 7.1 has not resolved.
3. **Never pass `--yes` unprompted.** That flag exists to skip `gh`'s own guard; removing a
   guardrail silently is not this door's job.

### 7.3 — Closing what finished

**Nothing else in this family closes an epic parent.** `dev:create-epic` writes a `## Done when`
described as *"observable, epic-level — true only when every child is closed"* — the epic states its
own completion condition and no door evaluates it. Phase 14 writes `Closes #N` for the **child**;
the parent stays open forever, and the board degrades as it gets more use.

This door already computes the number, so it does the check:

- epic reaches `n/n` → **offer** to close the parent, quoting its `## Done when`
- every epic in a milestone closed → **offer** to close the milestone

**Offer, never do.** Both are cancels in disguise, and a milestone closing is a release statement.

> Placed here rather than in `dev:pre-prod` because this is the door that already knows `n/n` and is
> already allowed to write. `dev:pre-prod` carries a one-line nudge at last-sibling merge, which is
> the moment it happens; this is the sweep that catches what the nudge missed.

## Never

- **Never cut a branch and never start work.** Naming a card hands to `/dev #N`.
- **Never file an issue** — that is `/dev:create-bug` / `create-issue` / `create-epic`.
- **Never write without naming `owner/repo#N` first** (Phase 2).
- **Never delete a branch.** Phase 7 writes to issues, not to refs — ORPHANED is a report.
- **Never offer an epic parent with open children as startable** (4.1).
- **Never call `gh issue view` per row** — the list call already has the fields, `body` included.
- **Never treat a stale local branch as in flight** — require unmerged commits (4.2).
- **Never render an auth failure as an empty board.**
- **Never render another repo's board** because this one's is empty (Phase 2).
- **Never invent work to fill an empty board** (6b). Surface only gaps the repo already wrote down;
  "this repo records no gaps" is a complete answer.
- **Never show a phase without state to back it** (4.4). Blank is honest.
- **Never bulk-relabel a tracker.** Applying `P1` to 200 issues invents 200 priorities. If the repo
  lacks `P1`/`P2`/`P3`, offer to create the labels — then leave them unapplied and fall back to one
  flat list ordered by age.

> **The clause that could not be ported.** `dev:issues` opened this list with *"Never cut a branch,
> never edit an issue, never start work. **Read-only is the whole contract.**"* This door edits
> issues by design, so that sentence is gone — and its protection is replaced by the bounded tiers
> in Phase 7, not simply dropped. If a future edit makes writes free rather than bounded, this door
> has become something the family did not agree to.

## Known limits

| | |
|---|---|
| Priority comes from `P1`/`P2`/`P3` labels | A repo without them gets one flat list ordered by age. **No inference — a guessed priority is worse than none** |
| Sub-issue detection reads the epic's body | GitHub's native sub-issues are not in `gh issue list` output; a task list or explicit refs is what is parsed. An epic whose body links nothing reads as childless |
| `--limit 200` | Larger trackers are truncated, and the render says so rather than reporting a partial count as the total |
| Closed count is a lifetime number | Not velocity. Throughput over time is not computed and is not claimed |
| `queue` needs a milestone | A repo with none has no queue column until `dev:roadmap` makes one. It is not an error |
| The phase column needs `.dev/` | Absent state means an absent column, never a guess |

## Scar tissue

**2026-08-05 — bare `/dev` had no defined behaviour.** Entry 1's routing table had three rows —
issue ref, family name, free text — and **no row for empty input**. A bare `/dev` fell toward the
free-text row, whose Entry 2 reads *"the argument text is the feature description"*; with no
argument there is no seed, so the outcome was whatever got improvised, up to and including cutting
a branch for an invented feature at Phase 3. This door is that missing row.

**2026-08-05 — first run against a real tracker found two design errors** (15 open / 135 closed).
Both are written up at 4.1 and 4.3: a bare `#N` grep invented an epic child and would have reported
1/5 instead of 0/4, and two branches carrying 7 unmerged commits between them were invisible because
their issues are closed. The first was caught only because the *right* answer and the *wrong* answer
differed — the earlier draft printed `0/4` correctly by luck, from a method that computes `1/5`.

**2026-09-10 — the rules moved into code, and the scar came with them.** Phases 3–5 are now also
`scripts/dev.py`, where 4.1's parse is a tested function whose fixture is that exact epic body —
four checklist children plus the same roadmap issue twice in prose. The prose above remains the
specification; the code is an implementation of it, and the fallback in Phase 0 exists so this door
never depends on it.

**Proven:** the single-fetch shape, the priority mix, the epic-parent-not-startable rule, the
task-list child parse, and the unmerged-commit test (a merged branch correctly silent at 0, two
unmerged ones correctly flagged).

**Undated, therefore unproven:** CURRENT detection from a branch name, slice ordering, the `stats` /
`all` / label-filter arguments, the whole of Phase 7 (no write has yet been made through this door),
and the QUEUE column (no repo it has run against has had a milestone).
