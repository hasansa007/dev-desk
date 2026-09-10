---
name: issues
description: >
  The TRACKER VIEW — what you are on, what is next, and the shape of the backlog, in one screen.
  Reads the repo's GitHub issues once and classifies them: CURRENT (the issue your branch maps to),
  IN FLIGHT (a branch exists with unmerged commits), NEXT (startable, priority-ordered), DEFERRED
  (epic-leftover). Then reports the counts — priority mix, epic progress, open vs closed — and asks
  which to start. Bare `/dev` with no argument routes here.
  Strictly READ-ONLY: it never cuts a branch, never edits an issue, never starts work. Naming one
  hands off to `/dev #N`.
  Trigger on: "what should I work on", "what's next", "show the issues", "show the backlog",
  "tracker", "issue stats", "what's in flight", "how many open issues", "what am I working on".
allowed-tools: [gh, git]
---

# issues — the tracker view

A **tool**, not a phase. Read-only by construction: it answers *"what should I work on?"* and hands
off. **It never cuts a branch and never edits an issue** — that is `/dev #N` and `/dev:create-*`.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | CURRENT + IN FLIGHT + NEXT + the counts | this |
| `stats` | the counts only, no list | full view |
| `all` | include P3 and DEFERRED in NEXT | top of each bucket |
| A label (`payments`, `P1`, `epic`) | filter to it | no filter |

## Phase 2 — Resolve the repo

Read `~/.claude/skills/dev/shared/entry.md` — repo auto-detect and pre-prod branch
resolution. Both are needed: the repo to query, the pre-prod branch to measure "unmerged" against.
Do not restate that logic.

**The resolved repo is a BOUNDARY, not a hint.** Render the board for that repo and no other. An
empty board *is* the answer when the tracker is empty — do not go looking for a fuller one
elsewhere. Another repo's backlog is a **sentence you may say**, never a board you render:
*"nothing here; the other checkout has 11 open — want that board instead?"* and then stop until
asked.

> **2026-08-05 — observed, in this skill's own first week.** Invoked from a repo whose tracker has
> never held an issue, it correctly reported zero — then offered to run against a different repo,
> did so, and rendered a board of that repo's issues and branches. The user's next message was
> *"what branch, what repo?"*, because two repos' state had been merged into one answer with
> nothing marking the seam.
>
> `dev:launch` 2.2 already carries this rule — *"A session can reach many repos; exactly one of them
> is `$PROJECT_ROOT`"* — and it was written after the same mistake in the same week. A board is more
> tempting to widen than a launch, because an empty board feels like a failure to be fixed. It is
> not: **an empty tracker is a finding, and a full board from the wrong repo is worse than nothing.**

## Phase 3 — Fetch once

```bash
gh issue list --state open --limit 200 \
  --json number,title,labels,updatedAt,createdAt
```

**One call, not one per issue.** `gh issue view` per row turns a 15-issue tracker into 15 round
trips for data the list already returned. Fetch closed **counts** separately and only for stats:
`gh issue list --state closed --limit 500 --json number -q 'length'`.

If the repo has no issues or `gh` is not authenticated, say so plainly and stop — an empty board and
a failed query must never render the same.

## Phase 4 — Classify

Four buckets, in this order. An issue lands in the first that matches.

| Bucket | Test |
|---|---|
| **CURRENT** | the current branch maps to it — `gh-<N>-…`, `<N>-…`, or an open PR whose head is this branch |
| **IN FLIGHT** | a branch exists for it **and** carries commits not in the pre-prod branch |
| **DEFERRED** | labelled `epic-leftover` — deferred deliberately, not forgotten |
| **NEXT** | everything else that is **startable** (see 4.1) |
| **ORPHANED** | a branch with unmerged commits whose issue is **closed**, or that maps to no issue — see 4.3 |

### 4.1 — An epic parent is not startable

An issue labelled `epic` **with open children is never offered as NEXT.** Offer its first unstarted
child instead, and show the parent only as progress (`#E <epic title> 0/4`).

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
> is **0/4**, nothing started. An epic whose progress
> bar is wrong is worse than one with no progress bar, because it is the number you would plan from.
> Epics cross-reference roadmaps, superseded issues and spin-offs constantly; only the checklist is
> a parent-child claim.

Count progress over **all** children, open and closed — an epic that is `3/4` done reads nothing
like `1 open`. That needs each child's state, which the open-only fetch in Phase 3 does not have,
so query the children explicitly.

An `epic` label with **no** open children is just an issue — treat it as startable.

### 4.2 — "Unmerged" needs the right base

A branch is only IN FLIGHT if `git rev-list --count <pre-prod>..<branch>` is non-zero. Measuring
against `main` in a two-stage repo marks everything already merged to pre prod as still in flight —
a board that reports finished work as unfinished is worse than no board.

Local branches accumulate: a real repo carried branches for long-since-merged issues, dozens of them.
**A branch existing proves nothing; only unmerged commits do.**

### 4.3 — Unmerged work on a CLOSED issue is the finding, not a filter miss

A board built only from `--state open` cannot see this, and it is the state most worth seeing.

> **2026-08-05, on the first run against a real tracker.** Two branches carried **5** and **2**
> unmerged commits — and both of their issues were **CLOSED**. So either the issues were closed
> while work was still outstanding, or the branches are abandoned and should be deleted. Both
> readings need a human; neither is visible from the open list. By contrast a third branch of
> similar age had 0 unmerged commits — genuinely stale, and correctly silent.

Report ORPHANED as **one warning line, never as work to start**, and say which of the two readings
it is only if you can tell. Do not delete branches — this skill is read-only.

## Phase 5 — Order NEXT

1. **Priority label** — `P1` → `P2` → `P3`. Unlabelled sorts *after* `P3`: unprioritised is not
   urgent, and silently promoting it would make the label meaningless.
2. **Slice order within an epic** — `Slice 1` before `Slice 2`. Never offer slice N+1 while slice N
   is open; the numbering is a dependency statement.
3. **Oldest `updatedAt` first** inside a tie — the thing that has been ignored longest.

Show the top 2–3 of NEXT by default, not all 15. A board you have to scroll is a board you skip.

## Phase 6 — Render, then ask

```
## <repo> — 15 open / 135 closed

CURRENT   none — on `<pre-prod>`, clean tree

NEXT      #A   P1  <title of the oldest untouched P1>
          #B   P1  <title of the next P1>
          #C   P2  <title of the oldest P2>

P1 2 · P2 5 · P3 8 · unlabelled 0
epics 2   #E <epic> 0/4 slices · #F <epic, no children — startable>
deferred  4 epic-leftover        (show with `all`)

ORPHANED  <branch-1>  5 commits, its issue CLOSED
          <branch-2>  2 commits, its issue CLOSED

→ start #A, or name another?
```

**End by asking, never by listing.** The board exists to produce a decision; stopping at the list
leaves the user to re-type a number you already know. Naming one hands to `/dev #N` — this skill
does not start it.

## Phase 6b — When NEXT is empty, read what the repo says about ITSELF

Fires only when NEXT has nothing — an empty tracker, or every issue classified into another bucket.
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

## Never

- **Never cut a branch, never edit an issue, never start work.** Read-only is the whole contract.
- **Never offer an epic parent with open children as startable** (4.1).
- **Never call `gh issue view` per row** — the list call already has the fields.
- **Never treat a stale local branch as in-flight** — require unmerged commits (4.2).
- **Never render an auth failure as an empty board.**
- **Never render another repo's board** because this one's is empty (Phase 2).
- **Never invent work to fill an empty board** (6b). Surface only gaps the repo already wrote down;
  "this repo records no gaps" is a complete answer.

## Known limits

| | |
|---|---|
| Priority comes from `P1`/`P2`/`P3` labels | A repo without them gets one flat NEXT list ordered by age. No inference — a guessed priority is worse than none |
| Sub-issue detection reads the epic's body | GitHub's native sub-issues are not in `gh issue list` output; a task list or explicit refs is what is parsed. An epic whose body links nothing reads as childless |
| `--limit 200` | Trackers larger than that are truncated; say so rather than reporting a partial count as the total |
| Closed count is a lifetime number | Not velocity. Throughput over time is not computed and is not claimed |

## Scar tissue

**2026-08-05 — bare `/dev` had no defined behaviour.** Entry 1's routing table had three rows —
issue ref, family name, free text — and **no row for empty input**. A bare `/dev` fell toward the
free-text row, whose Entry 2 reads *"the argument text is the feature description"*; with no
argument there is no seed, so the outcome was whatever got improvised, up to and including cutting
a branch for an invented feature at Phase 3.

The file already carried the neighbouring scar — *"`/dev run` would branch `feature/run` and start
building a feature called 'run'. Observed 2026-08-04"* — and its guard catches a **one-word**
argument while leaving the **zero-word** one, which is strictly more ambiguous, unhandled. This
skill is that missing row: the emptiest possible input now produces the most useful possible answer.

**2026-08-05 — first run against a real tracker found two design errors** (15 open
/ 135 closed). Both are written up at 4.1 and 4.3: a bare `#N` grep invented an epic child and would
have reported 1/5 instead of 0/4, and two branches carrying 7 unmerged commits between them were
invisible because their issues are closed. The first was caught only because the *right* answer and
the *wrong* answer differed — the earlier draft printed `0/4` correctly by luck, from a method that
computes `1/5`.

**Proven:** the single-fetch shape, the priority mix, the epic-parent-not-startable rule, the
task-list child parse, and the unmerged-commit test (a merged branch correctly silent at 0, two
unmerged ones correctly flagged).

**Undated, therefore unproven:** CURRENT detection from a branch name (no issue-mapped branch was
checked out at the time), slice ordering, and the `stats` / `all` / label-filter arguments.
