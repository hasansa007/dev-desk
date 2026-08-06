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

Read `~/Developer/skills/dev-skill/shared/entry.md` — repo auto-detect and pre-prod branch
resolution. Both are needed: the repo to query, the pre-prod branch to measure "unmerged" against.
Do not restate that logic.

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
child instead, and show the parent only as progress (`#174 Podcast 0/4`).

This is the family's own rule, not a preference — `README.md`: *"split it at Phase 5 into real
sub-issues, run `/dev #child` per slice — the sub-issue list IS the queue."* Starting `/dev #174`
would re-enter decomposition on an epic that is already decomposed.

**Parse the TASK LIST, never a bare `#N` grep.** Children are the checklist lines; anything else is
prose:

```bash
gh issue view <epic> --json body -q .body \
  | grep -E '^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*#[0-9]+'
```

> **2026-08-05 — a bare grep invented a child.** Epic #174's body references `#179` twice in prose
> (*"see the Roadmap issue #179"*, *"Roadmap context: #179"*) while its actual children are four
> `- [ ] #N` lines, #175–#178. Grepping `#[0-9]+` returns five children, one of them closed, and
> reports the epic as **1/5 done**. The truth is **0/4** — nothing started. An epic whose progress
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

Local branches accumulate: this repo's daily driver carried `gh-14` … `gh-265` long after merge.
**A branch existing proves nothing; only unmerged commits do.**

### 4.3 — Unmerged work on a CLOSED issue is the finding, not a filter miss

A board built only from `--state open` cannot see this, and it is the state most worth seeing.

> **2026-08-05, on the first run against a real tracker.** `gh-113-course-roster` carried **5**
> unmerged commits and `gh-265-account-delete` **2** — and issues #113 and #265 are both **CLOSED**.
> So either the issues were closed while work was still outstanding, or the branches are abandoned
> and should be deleted. Both readings need a human; neither is visible from the open list.
> By contrast `gh-14-opus-json-build-hardening` had 0 unmerged commits — genuinely stale, correctly
> silent.

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
## studyhub-deploy — 15 open / 135 closed

CURRENT   none — on `staging`, clean tree

NEXT      #462  P1  Append flow: reuse the create wizard's per-video…
          #60   P1  Content-addressed build cache — reuse existing…
          #401  P2  App-shell landmarks: <main> + skip-to-content

P1 2 · P2 5 · P3 8 · unlabelled 0
epics 2   #174 Podcast 0/4 slices · #547 native client
deferred  4 epic-leftover        (show with `all`)

ORPHANED  gh-113-course-roster  5 commits, issue #113 CLOSED
          gh-265-account-delete 2 commits, issue #265 CLOSED

→ start #462, or name another?
```

**End by asking, never by listing.** The board exists to produce a decision; stopping at the list
leaves the user to re-type a number you already know. Naming one hands to `/dev #N` — this skill
does not start it.

## Never

- **Never cut a branch, never edit an issue, never start work.** Read-only is the whole contract.
- **Never offer an epic parent with open children as startable** (4.1).
- **Never call `gh issue view` per row** — the list call already has the fields.
- **Never treat a stale local branch as in-flight** — require unmerged commits (4.2).
- **Never render an auth failure as an empty board.**

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

**2026-08-05 — first run against a real tracker found two design errors** (studyhub-deploy, 15 open
/ 135 closed). Both are written up at 4.1 and 4.3: a bare `#N` grep invented an epic child and would
have reported 1/5 instead of 0/4, and two branches carrying 7 unmerged commits between them were
invisible because their issues are closed. The first was caught only because the *right* answer and
the *wrong* answer differed — the earlier draft printed `0/4` correctly by luck, from a method that
computes `1/5`.

**Proven:** the single-fetch shape, the priority mix, the epic-parent-not-startable rule, the
task-list child parse, and the unmerged-commit test (`gh-14` correctly silent at 0, `gh-113`/`gh-265`
correctly flagged).

**Undated, therefore unproven:** CURRENT detection from a branch name (no issue-mapped branch was
checked out at the time), slice ordering, and the `stats` / `all` / label-filter arguments.
