---
name: ideation
description: >
  Reads an EXISTING app and reports what is worth DOING to it — concrete opportunities in
  performance, security and quality. Not defects: `dev:survey` owns those. This door asks the other
  question, of the same code — "what does this do adequately that could be materially better?"
  Every opportunity is adversarially verified against the code before it can be filed, and the
  evidence standard is a NUMBER, not a narrative: a claim with no measurement, complexity argument
  or count is held, never filed. "Could be faster" is a preference, and preferences do not belong in
  a tracker.
  Files confirmed opportunities as `enhancement`, never as bugs. Writes `docs/ideation/<date>.md`
  first; filing is a separate confirmed step.
  Trigger on: "what could we improve", "find performance problems", "any security concerns",
  "where is this slow", "ideation", "what's worth optimising", "quality wins", "technical debt
  worth paying", "what should we improve next".
allowed-tools: [git, gh, rg, grep, Read, Write, Agent]   # Read: every verdict is read-backed. Write: the report. Agent: one surveyor per flow.
---

# ideation — what is worth doing to this app

A **tool**, not a phase, and it sits **upstream of Phase 0**, beside `dev:survey`.

**Two doors, two questions, one codebase:**

| Door | Asks | Files as |
|---|---|---|
| `dev:survey` | *what does this do that it should not?* — defects, and architectural drift | bug · ADR · epic |
| **`dev:ideation`** | *what does this do adequately that could be materially better?* | `enhancement` |

**Run one, not both, unless you mean to.** They discover the same flows and fan out the same way, so
running both doubles the largest spend in the family. If you want everything, say so and run
`dev:survey` first — a defect outranks an improvement, and knowing what is broken changes which
improvements are worth making.

**It suggests. It never implements.** No fix, no refactor, no rewrite, not even an obvious one. The
output is a report and, on confirmation, issues. `/dev #N` does the work afterwards.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | every flow it can discover | this |
| A flow name (`checkout`) | that flow only | all |
| `--perf` | performance opportunities only | all three kinds |
| `--security` | security opportunities only | all three kinds |
| `--quality` | duplication and coupling only | all three kinds |

## Phase 2 — Resolve the repo, then read what is already tracked

**Identical to `dev:survey` Phase 2, which is the source of truth for it** — read that door's Phase 2
and apply it unchanged: the absolute path to `shared/entry.md` because this runs inside somebody
else's repo, the resolved repo as the boundary for reading, writing and filing, and the **per-path
dedupe** with its reason (the match key lives in the issue *body*, which a bulk `--json
number,title,labels` list does not return at all).

One addition: **dedupe against closed issues too.** An opportunity declined once should not be
re-proposed. `dev:survey` searches open issues because a closed bug is a fixed bug; a closed
`enhancement` is often a *rejected* one, and re-filing it is how a tracker loses trust.

```bash
gh issue list --repo <owner/repo> --state all --search "<path> in:title,body" \
  --json number,title,body,state,stateReason
```

A match closed as `not planned` is a **decision**, not a gap. Report it as *declined <date>* and
file nothing.

## Phase 3 — Discover the flows from evidence

**Identical to `dev:survey` Phase 3.** Read it and apply it unchanged — flows from what the repo
declares, `git ls-files` rather than a directory walk, and the fallback to one directory below the
source root labelled **modules, not flows**.

## Phase 4 — Fan out, one surveyor per flow

**The fan-out mechanics are `dev:survey` Phase 4** — one flow per agent never two, `/tasks` for live
progress, the per-surveyor record of finding count and **done-with-nothing vs died**, the Right-Size
declaration before spending, and the propose-a-narrowing rule above 12 flows. Name the flow in each
task description (`ideation: checkout`).

### What an opportunity surveyor returns

The same standard as a bug finding, translated. Each carries **the current behaviour measured or
derived from the code, the proposed change, and the expected gain with its unit**:

| Kind | What makes it a finding rather than a preference |
|---|---|
| **Performance** | the cost read off the code — an N+1 named with its call site, an O(n²) with n's real bound, a synchronous call on a render path. **Not** "this looks slow" |
| **Security** | the reachable path from untrusted input to the sink, with both named |
| **Quality** | the duplication or coupling **counted**, with the files listed |

**"Could be faster" is not an opportunity.** Neither is "should use a newer library", nor "this
would be cleaner with X". If the gain cannot be stated with a number, a unit or a count, it is a
preference — and preferences filed into a tracker are indistinguishable from work.

**Report the bound, not just the shape.** An O(n²) over a list that is always three items long is
not an opportunity. Naming the complexity without naming *n* is how a rewrite gets justified by
arithmetic that never applied.

## Phase 5 — Verify adversarially, before anything is filed

**Never skipped.** The protocol is `dev:survey` Phase 5 and that door is its source of truth: **two
independent checkers per finding, each prompted to refute it**, each opening the named file and its
callers rather than reasoning from the finding's own text; checkers never see each other's verdict;
**disagreement resolves to PLAUSIBLE, never CONFIRMED**; REFUTED findings are listed with their
refutation, not merely counted.

**Checkers scale on findings, not flows** — five opportunities in one flow costs ten checkers, so
the declared estimate is a floor and not a bound.

### An opportunity is verified differently from a defect

A bug checker asks *does the code do this?* An opportunity checker asks **two** things, and **both**
must hold or the verdict is PLAUSIBLE:

1. **Is the current behaviour as described?** Read it. Do not accept the finding's own summary.
2. **Would the proposed change actually produce the claimed gain?** A refactor that **moves** a cost
   rather than removing it is **REFUTED**, not CONFIRMED, however tidy the result.

**A performance claim with no measurement and no complexity argument is PLAUSIBLE by default**, not
CONFIRMED. "Probably faster" has exactly the standing of "probably broken", and the whole point of
this phase is that neither reaches a tracker.

> **Why this is stricter here than for defects, not looser.** The instinct is to treat an
> improvement as low-risk and wave it through. It is the opposite. A bug that turns out not to exist
> costs one close. An "optimisation" that moves a cost rather than removing it costs a whole branch,
> passes review, merges — and looks like a success. Nothing downstream will catch it.

## Phase 6 — Rank by gain over cost, and say both

An opportunity's existence is not an argument for doing it — that is the difference from a defect.
So each confirmed one carries **the gain and the estimated cost**, and the ranking is the ratio.

State the **cost of doing nothing** for each. If it is "nothing measurable", say that: it is an
honest answer and it is usually the right one.

**Never rank by how interesting the work is.** The most enjoyable refactor in a codebase is rarely
the one with the best ratio, and this phase exists to make that visible rather than to launder it.

## Phase 7 — Write the report

`docs/ideation/<YYYY-MM-DD>.md`, and `<date>-<HHMM>.md` for every later run that day. Create
`docs/ideation/` if the repo has no `docs/`, and say that you did.

**Writing the report is a write, and the write boundary applies** (`shared/entry.md` rule 3): name
`owner/repo`, and **cut a branch before creating the file** rather than dropping a tracked file onto
whatever branch the developer is standing on. Check `git check-ignore -q docs/` and say which answer
you got — if `docs/` is ignored the report is a local working file and a reader should not be sent
looking for it in the clone.

**Sections whose kind was skipped by a flag are omitted, never left empty.** An empty PERFORMANCE
reads as *nothing found*, which is a different and much worse claim than *not looked for*.

```
# Ideation — <repo> — <date>
Flows: <n>, from <where they were declared>   Kinds: <perf | security | quality>

## CONFIRMED (n)                     ← eligible to file as `enhancement`
- <current, measured or derived> → <proposed>
  gain: <number + unit, or count>    cost: <estimate>    doing nothing: <what it costs>
  <file:line>                        touches: <paths>

## PLAUSIBLE (n)                     ← held, not filed
- <claim> · why it could not be confirmed from the code

## REFUTED (n)
- <claim> · <the refutation — including "moves the cost, does not remove it">

## DECLINED BEFORE (n)               ← closed as not planned; a decision, not a gap
- <claim> · #N · declined <date>

## ALREADY TRACKED (n)

## COST
<the `dev:survey` Phase 7 COST format, verbatim — declared vs actual, per-flow table,
 FAILED rows included, wall time reported separately from the sum>
```

## Phase 8 — Walk it through, one at a time (BEFORE the filing offer)

**The gate is `dev:survey` Phase 8 and that door is its source of truth**: state the mechanism and
constraints, **then STOP**; ask how they would handle it; only then give yours and diff the two
explicitly; print the `alternatives considered` / `rejected:` line either way, *especially* when it
is empty. `just do it` skips one, `just do it all` skips the rest. **Never batch.**

**One extra question here, and it has no equivalent for a defect: is it worth doing at all?**

A bug's existence is the argument for fixing it. An opportunity's is not. ***"Confirmed, and I would
still not do it"* is a complete and common answer** — record it as DECLINED with the reason, and file
it closed as `not planned` so Phase 2 reads it back and the next run does not re-propose it.

## Phase 9 — Offer to file

Ask before filing anything. Then, for the confirmed set:

- **`dev:create-issue`, labelled `enhancement`.** Never `dev:create-bug`. Filing an improvement as a
  defect makes the board lie about how broken the app is, and `dev:kanban` ranks from that board.
- **The measured current behaviour and the claimed gain go in the body**, with the `file:line`. An
  enhancement whose body says only "improve performance" is a task nobody can start.
- **Name this run in `## Suspected`, and say what the verdict does NOT cover:** *"found by
  `dev:ideation` <date>; two checkers confirmed the mechanism and the gain against the code — not
  measured at runtime."* Without the line the issue is indistinguishable from a hand-written one and
  the adversarial verification is spent twice.
- **Touched files go in `## Scope`.** Two issues touching one file are **conflicting, not
  blocking** — say so in both and let whoever starts second rebase.
- **Set a priority label from the Phase 6 ranking.** `dev:kanban` Phase 5 orders the backlog by
  `P1 → P2 → P3` then slice then oldest; ten issues filed the same minute share a timestamp, so
  without labels the ranking dies in the report.
- **Carry Phase 6's two numbers into labels:** the gain becomes `impact:`, the cost becomes
  `complexity:`. This door is the one that already computed them, so filing without them throws away
  the arithmetic that produced the ranking. Both stay proposals the developer corrects
  (`docs/guide/WORKFLOW.md` → *Rating an issue*); a missing label is offered, never created silently.
- **File at most 10 per run, and name what was held.**
- **An opportunity never outranks an open defect.** If `dev:survey` has confirmed bugs waiting, say
  so when handing off: a tracker that fills with improvements while defects wait is one nobody
  trusts.

**Write the structured twin.** Alongside `docs/ideation/<date>.md`, write `docs/ideation/<date>.json`
with the same findings — verdict, `file:line`, gain, cost. The markdown is the human artifact and the
JSON the machine-readable one; **generate the markdown FROM the JSON** so the two cannot
disagree. Then point the developer at `docs/ideation/<date>.md` — the report is the view.

## Never

- **Never implement.** Not a fix, not a rename, not an obvious one-liner. Suggest only.
- **Never file a PLAUSIBLE finding**, and never file without asking.
- **Never file an opportunity as a bug** — that is `dev:survey`'s output, not this door's.
- **Never file a gain with no number, unit or count.** That is a preference.
- **Never re-propose something closed as `not planned`** (Phase 2). A decision is not a gap.
- **Never recommend a rewrite.** If the honest answer is *"leave it"*, that is the finding.
- **Never show the fix before asking for theirs.** Phase 8 is worthless the instant an answer is on
  screen; anchoring is not undone by asking politely afterwards.
- **Never invent a flow, a finding, or a count.** `shared/entry.md`'s *a result is not a claim*
  applies to every number in the report.
- **Never run against a repo other than the resolved one.**

## Next — ask, never stop flat

`shared/entry.md` → *Never end silently* applies here as to every sibling.

Report written → **walk them through (Phase 8)** → offer the filing, naming the branch it would cut.
Filed → name the first by gain-over-cost and hand to `/dev #N`. **Nothing worth doing → say so
plainly, name what was covered, and offer `dev:survey`** — "this app has no opportunities worth the
cost" is a real and valuable answer, and it is also the moment to ask whether anything is *broken*,
which is the other door's question.

## Scar tissue

**2026-09-10 — split out of `dev:survey`, hours after being merged into it.** The first attempt gave
`dev:survey` a third hunt and renamed the whole door `dev:ideation`. That name was wrong: two of its
three hunts were defect-finding, and finding a null-deref is not ideation. The split restores
`dev:survey` byte-identical and leaves this door with the one hunt the name actually describes.

**The cost of the split, accepted knowingly:** two doors discover the same flows and fan out the
same way, so running both doubles the family's largest spend. The intro says run one. The
alternative — one door with three hunts — was rejected because a name that misdescribes two-thirds
of what a door does is a name that will mislead someone into skipping it.

**Undated, therefore unproven:** this door has never been run. Its finding rate, its checker cost,
the gain-over-cost ranking in Phase 6, and the closed-issue dedupe in Phase 2 are all designed
rather than observed.
