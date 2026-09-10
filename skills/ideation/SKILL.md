---
name: ideation
description: >
  Reads an EXISTING app and reports what is wrong with it and what is worth doing to it — real bugs,
  the architectural drift between the patterns actually in use, and concrete opportunities
  (performance, security, quality) — then files the confirmed ones. It suggests and never
  implements: no fix, no refactor, no rewrite.
  Every finding is adversarially verified against the code before it can be filed, because a tracker
  full of plausible-but-wrong issues is worse than an empty one and `dev:kanban` will rank it either
  way. Unverified findings are held in the report with the reason, never filed.
  Writes `docs/ideation/<date>.md` first; filing to GitHub is a separate confirmed step. Fans out one
  surveyor per flow, and shapes what it files so several issues can be started at once.
  Replaces `dev:survey`, whose rules it carries unchanged.
  Trigger on: "what's wrong with this app", "find the bugs in this codebase", "survey the code",
  "ideation", "what could we improve", "find performance problems", "any security concerns",
  "audit the architecture", "is this MVVM or clean", "the architecture is inconsistent",
  "what should we fix", "what should we build next", "review the whole app".
allowed-tools: [git, gh, rg, grep, Read, Write, Agent]   # Read: every verdict is read-backed. Write: the report. Agent: one surveyor per flow.
---

# ideation — read the app, report what is wrong and what is worth doing, file the confirmed

A **tool**, not a phase, and it sits **upstream of Phase 0**. `dev:kanban` renders the board;
nothing stocked it. Every door from Phase 0 on assumes you already know what is wrong — this is the
one that finds out.

**It suggests. It never implements.** No fix, no refactor, no rewrite, not even an obvious one.
The output is a report and, on confirmation, issues. `/dev #N` does the work afterwards.

> **Replaces `dev:survey`.** Its rules are carried unchanged; the only addition is the third hunt in
> Phase 1. Anything below marked *verbatim* survived the rename untouched.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | every flow it can discover, all three hunts | this |
| A flow name (`checkout`) | that flow only | all |
| `--bugs` | Phases 4 + 5, defects only | all three |
| `--arch` | Phase 6 only — skip Phases 4 and 5 entirely | all three |
| `--opportunities` | Phases 4 + 5, opportunities only | all three |

### The three hunts ask different questions of the same code

| Hunt | Question | Output |
|---|---|---|
| **bugs** | *what does this do that it should not?* | `dev:create-bug`, one per finding |
| **opportunities** | *what does this do adequately that could be materially better?* | `dev:create-issue`, labelled `enhancement` |
| **architecture** | *do the patterns in use agree with each other?* | an ADR or an epic — **never a pile of bugs** |

**An opportunity is not a bug and must not be filed as one.** A bug means the code is wrong; an
opportunity means it is correct and improvable. Filing an improvement as a bug makes the board lie
about how broken the app is, and `dev:kanban` ranks from that board.

**Opportunities multiply findings, and Phase 5 costs two checkers each.** Running all three hunts on
a flow that yields 5 bugs and 5 opportunities is 20 checkers, not 10. Say so when declaring the
fan-out in Phase 4 — the floor moves, not just the total.

## Phase 2 — Resolve the repo, then read what is already tracked

Read `~/.claude/skills/dev/shared/entry.md` — **the absolute path, because this skill runs
inside somebody else's repo**, where a bare `shared/entry.md` resolves to a file that does not
exist. The resolved repo is the boundary, for reading, for writing and for filing.

Also read `~/.claude/skills/dev/shared/pipeline.md` → **Guiding Principles, Universal Rules,
and Right-Size the Process**. Right-Size is not optional here despite this being a tool: it owns the
fan-out rule, and Phases 4 and 5 are the largest fan-out in the family.

**A run that files something already in the tracker has made the board worse.** Dedupe runs at
Phase 9, once findings name files — **searched per path, never as a bulk list**:

```bash
gh issue list --repo <owner/repo> --state open --search "<path> in:title,body" \
  --json number,title,body
```

**Why per-path and not `--limit 200`.** The match key is the file path plus the symptom, and both
live in the **body** — which `--json number,title,labels` does not return at all, so a bulk list
cannot dedupe even in principle. Searching also has no 200-issue ceiling to silently truncate
behind, which `shared/entry.md`'s *scope limiter* rule forbids relying on. `--repo` is explicit
because the surveyed repo is the resolved one, not whatever `cwd` points at.

**If `gh` errors or the repo has Issues disabled, say so and stop.** An empty result and a failed
query must never render the same — `dev:kanban` Phase 3's rule, and the reason it exists is that a
failed dedupe files every finding as new.

When a match is uncertain, file nothing and report **possible duplicate of #N**: a wrong merge hides
a real bug, a wrong split costs one close.

## Phase 3 — Discover the flows from evidence

A **flow** is a user-reachable path through the app: an entry point plus the code it exercises.
Find them from what the repo declares, never from imagination —

| Stack | Where flows are declared |
|---|---|
| Next.js / React Router | `app/**/page.*`, `pages/**`, route definitions |
| iOS | coordinators, `NavigationStack` destinations, storyboard segues |
| Android | nav graph, `NavHost` composable destinations |
| Any | HTTP handlers, CLI subcommands, queue consumers, cron entry points |

**Print the flow list and its source before surveying.** A flow you cannot point at a declaration
for is one you invented, and every finding under it inherits that.

If nothing declares flows, say so and fall back to **one directory below the source root** — the
same unit `dev:comment-budget` uses, and for the same reason: it has to be small enough that one
surveyor's pass fits one context.

**Enumerate with `git ls-files`, never with a directory walk.** Tracked files only means build
output, vendored trees and anything `.gitignore`d are excluded *by construction* — `node_modules`,
`dist`, `.next`, `Pods`, `target` — rather than by a blocklist that needs a new entry per ecosystem
forever. A surveyor auditing compiled assets burns a whole agent to find nothing. Label the results
**modules, not flows**; a finding under a module says *this code is wrong*, a finding under a flow
says *a user hits this*, and only the second can be ranked by cost. Everything downstream reads
"flow" as "flow or fallback unit".

## Phase 4 — Fan out, one surveyor per flow

**Skipped under `--arch`.** Otherwise dispatch one agent per flow
(`superpowers:dispatching-parallel-agents`). **One flow per agent, never two.** A whole codebase does
not fit one context, and a surveyor that runs out mid-flow does not announce it — it just returns
fewer findings, which reads exactly like a clean flow.

**Live progress is `/tasks`, not something this skill prints.** The harness already shows every
running subagent with its elapsed time and token count, live and continuously. **Name the flow and
the hunt in each agent's task description** (`ideation: checkout · bugs+opps`) so that view is
readable at a glance instead of six identical rows.

**What `/tasks` cannot show, and this skill must record**, per surveyor as it returns:

- **the finding count, split by hunt** — `/tasks` knows an agent finished, not what it concluded
- **done-with-nothing vs died** — both leave no findings, and they mean opposite things. A crashed
  surveyor read as a clean flow is the failure mode this whole phase exists to prevent
- **duration, tokens and tool calls at completion** — gone once the run ends; Phase 7 reconciles the
  estimate against them, and unrecorded, the estimate can never get better

**Declare the fan-out and get a word before spending it** (Right-Size): *"18 flows → 18 surveyors,
then ~2 checkers per finding across two hunts. Go, or narrow it?"* This is the family's largest
fan-out and Right-Size forbids opening one on the developer's behalf and reporting the bill
afterwards. **Above 12 flows, propose a narrowing first** rather than asking them to approve a
number they have no way to price.

### What each surveyor returns

**Bugs** — the symptom, the file and line, the **mechanism** that produces it, and what it expected
instead.

**A finding without a mechanism is a guess.** *"Open a course with 40+ lessons, scroll to lesson 30,
press back"* is a finding; *"navigation seems fragile"* is a feeling. This is `dev:create-bug`'s
`## Steps` standard applied one step earlier, and it is the whole difference between a survey and a
vibe.

**Opportunities** — the same standard, translated. An opportunity carries **the current behaviour
measured or derived from the code, the proposed change, and the expected gain with its unit**:

| Kind | What makes it a finding rather than a preference |
|---|---|
| Performance | the cost read off the code — an N+1 named with its call site, an O(n²) with n's real bound, a synchronous call on a render path — **not** "this looks slow" |
| Security | the reachable path from untrusted input to the sink, with both named |
| Quality | the duplication or coupling **counted**, with the files listed |

**"Could be faster" is not an opportunity.** Neither is "should use a newer library". If the gain
cannot be stated with a unit or a count, it is a preference, and preferences do not go in a tracker.

## Phase 5 — Verify adversarially, before anything is filed

**Never skipped.** `--arch` skips the bug *hunt*, not the verification: Phase 6's counts and drift
items are findings too, and an epic proposing the wrong target pattern is the costliest thing this
skill can file. A count is checked by recounting from the file list, independently.

Every finding gets **two independent checkers, each prompted to refute it**, and each must open the
named file and its callers rather than reasoning from the finding's own text. Two, not one: a
single checker that agrees produces a confirmation indistinguishable from a rubber stamp.

**Checkers are the larger spend, and they scale on findings, not on flows.** Two per finding
means a flow returning 5 findings costs 10 checkers — so the total is not knowable at Phase 4 and
the declared estimate is a floor, not a bound. Say so when declaring it, report checker progress the
same way as surveyors, and **stop and re-ask if the checker count passes twice the declared
estimate** rather than spending through it silently.

**Checkers never see each other's verdict**, and **disagreement resolves to PLAUSIBLE, never to
CONFIRMED** — the safe verdict is the one that holds the finding out of the tracker, since a wrong
CONFIRMED costs a close and a wrong PLAUSIBLE costs a line in a report.

This is not ceremony. **2026-08-23/24:** three review rounds over one skill returned 15, 15 and 15
findings; what separated the real ones was being checked against code rather than against how
plausible they sounded, and a fourth round still found more.

| Verdict | Meaning | Fate |
|---|---|---|
| **CONFIRMED** | the checker reproduced the reasoning against the code and could not refute it | eligible to file |
| **PLAUSIBLE** | it may be real; the checker could not confirm it from the code alone | **held in the report with the reason**, never filed |
| **REFUTED** | the code does not do what the finding claims | **listed in the report**, one line each, with the refutation |

**Refuted findings are listed, not just counted.** A checker told to refute will sometimes refute a
real bug, and a bare count leaves that unauditable and makes the next run re-derive it from scratch.
The report carries the symptom and the refutation so a human can overturn it.

A run that refutes **nothing** is a run whose checkers were agreeing rather than checking — the same
tell as `dev:comment-budget`'s "a run that keeps nothing". A run that refutes **almost everything** is the
opposite failure, and the list is what makes it visible.

### Verifying an opportunity is a different question

A bug checker asks *does the code do this?* An opportunity checker asks **two** things, and both
must hold or the verdict is PLAUSIBLE:

1. **Is the current behaviour as described?** — read it, do not accept the finding's summary.
2. **Would the proposed change actually produce the claimed gain?** A refactor that moves a cost
   rather than removing it is REFUTED, not CONFIRMED, however tidy the result.

**A performance claim with no measurement and no complexity argument is PLAUSIBLE by default**, not
CONFIRMED. "Probably faster" has the same standing in a tracker as "probably broken", and the whole
point of this phase is that neither gets filed.

## Phase 6 — The architecture pass — count before recommending

**Skipped under `--bugs` and under `--opportunities`.** Separate from both hunts, and it produces
**an ADR or an epic, never a pile of bug issues**.

1. **Name what is actually there, with counts.** *"11 screens: 7 MVVM, 3 MVC, 1 TCA"* — measured by
   reading them, and say how you counted.
2. **Recommend the pattern the codebase already mostly is.** Unification means moving the minority
   to the majority. Recommending TCA to a codebase that is 70% MVVM is a **rewrite wearing the word
   unify**, and it will not happen.
3. **List the drift as individual moves**, each one a slice someone could take.
4. **Never recommend a rewrite**, and never recommend a pattern absent from the codebase unless the
   developer asks for one. If the honest answer is *"it is already consistent"*, that is the finding.

State the cost of doing nothing, or the recommendation is a preference.

## Phase 7 — Write the report

**Under a flag, the sections whose source phase was skipped are omitted, never left empty.** An
empty CONFIRMED reads as *nothing found*, which is a different and much worse claim than *not
looked for*. The same applies to OPPORTUNITIES under `--bugs`.

`docs/ideation/<YYYY-MM-DD>.md`, and `<date>-<HHMM>.md` for every later run that day — two runs in
one day are usually a narrowed re-run, and overwriting the wider one loses the held PLAUSIBLE set.
The file is the artifact that makes the run reviewable and re-runnable; filing is a separate step,
so nothing reaches the tracker unread. Create `docs/ideation/` if the repo has no `docs/`, and say
that you did.

> **Reports written before 2026-09-10 are in `docs/survey/`.** Read both directories when looking
> for prior runs, and when `dev:roadmap` reads history. Do not move the old ones — a report is dated
> evidence, and relocating it breaks whatever cited it.

**Check whether the repo tracks it** — `git check-ignore -q docs/` — and say which answer you got. If
`docs/` is ignored the report is a local working file: still written, still read before anything is
filed, but not in the clone, so a reader should not be sent looking for it in the repo.

**Writing the report is a write, and the write boundary applies** (`shared/entry.md` rule 3): name
`owner/repo`, and **cut a branch before creating the file** rather than dropping a tracked file onto
whatever branch the developer is standing on. This is the one phase that is not read-only, and it
must not be described as if it were.

```
# Ideation — <repo> — <date>
Flows: <n>, from <where they were declared>   Hunts: <bugs | opportunities | architecture>

## CONFIRMED — BUGS (n)              ← eligible to file as bugs
- <symptom> · <file:line> · mechanism: <exact steps> · expected: <what should happen>
  touches: <paths>        blocks: <other finding, if same files>

## CONFIRMED — OPPORTUNITIES (n)     ← eligible to file as enhancements
- <current, measured or derived> → <proposed> · gain: <number + unit, or count>
  <file:line>             touches: <paths>

## PLAUSIBLE (n)                     ← held, not filed
- <symptom> · why it could not be confirmed from the code

## REFUTED (n)
- <symptom> · <the refutation>

## ARCHITECTURE
Actual: <counts, and how counted>   Recommend: <the majority pattern>   Cost of doing nothing: <…>
- <drift item> → <the move>

## ALREADY TRACKED (n)

## COST
Declared <shape>  ·  Actual <agents, wall, tokens, calls>  ·  Overrun <what and why, or none>
<per-flow table: findings, duration, tokens, calls — FAILED rows included>
```

### The `## COST` section — reconcile the estimate, or it never improves

Right-Size makes this skill declare a fan-out before spending it. Declaring without ever reporting
the actual is half a rule: the next run's estimate is then guesswork with a track record it cannot
read.

```
## COST
Declared   6 surveyors + ~2 checkers per finding  (floor: 12 agents)
Actual     6 surveyors + 14 checkers = 20 agents · 7m04s wall · 412k tokens · 231 tool calls
Overrun    +2 agents — one flow returned 5 findings where the floor assumed 2

Per flow          findings   duration   tokens   calls
  auth               2b 1o      1m12s      38k      14
  checkout               0        52s      21k       9
  account               1b       1m41s      47k      19
  admin              3b 2o      2m03s      61k      27   ← the overrun
  build              FAILED     0m14s       3k       2   ← died, NOT clean
  export                 0      1m08s      29k      11
```

- **A failed surveyor is a row, not a silence.** `FAILED` and `0 findings` mean opposite things and
  a missing row means neither. Whatever a dead flow leaves behind, it is not evidence of clean code.
- **Split the finding count by hunt** (`2b 1o`). A flow with two bugs and one opportunity costs six
  checkers, and a single number hides which hunt drove the spend.
- **Wall time is not the sum of the durations** when agents run concurrently. Report both: the sum
  is what it cost, the wall is what it felt like.
- **Run inline with no fan-out and this section says so**, with no per-agent figures invented. A
  sequential run has no per-agent data, and a plausible-looking table is worse than its absence.

## Phase 8 — Walk it through, one finding at a time (BEFORE the filing offer)

**The developer's stated purpose for this gate: build their own model of the system, not receive
one.** A finding they can restate is worth more than three they approved. So this phase is not a
summary — it asks first and answers second, on **every** confirmed finding, opportunities included.

For each, in order:

1. **State the mechanism and the constraints. Then STOP.** No fix, no recommendation, not even a
   hint of direction. The moment a proposed answer is on screen, whatever they say next is a
   reaction to it rather than their own reasoning, and the gate has produced nothing.
2. **Ask how they would handle it.** Wait for a real answer.
3. **Then give yours, and diff the two explicitly** — name where they agree, where they differ, and
   what each choice costs. If theirs is better, say so plainly and take it.
4. **Print the alternatives line either way:**
   - `alternatives considered: none — one correct form` for a mechanical finding, or
   - `rejected: <option> — <why it lost>`, one line each, for a real fork.

**That line is the audit.** It is how the developer sees whether a decision was presented as
mechanical when it was not — so it is printed even when it is empty, and *especially* then.

**An opportunity gets one extra question: is it worth doing at all?** A bug's existence is the
argument for fixing it; an opportunity's is not. *"Confirmed, and I would still not do it"* is a
complete and common answer — record it as REJECTED with the reason so the next run does not
re-propose it.

**`just do it` skips the current finding. `just do it all` skips the rest of the phase.** No
re-asking, no friction, no second attempt at persuasion — and the bulk form matters here more than
anywhere: this is the family's widest fan-out, so a 20-finding run without it costs 20 separate
escapes, which is the ceremony GUIDE principle 4 refuses.

**Never batch.** One finding, one answer, one diff. A list of five questions gets one answer about
the last one.

---

## Phase 9 — Offer to file, shaped for parallel work

Ask before filing anything. Then, for the confirmed set:

- Bugs → `dev:create-bug`, one per finding, mechanism carried into `## Steps` intact.
- **Opportunities → `dev:create-issue`, labelled `enhancement`**, with the measured current
  behaviour and the claimed gain carried into the body. Never `dev:create-bug` — see Phase 1.
- **Name this run in `## Suspected`, and say what the verdict does NOT cover:** *"found by
  `dev:ideation` <date>; two checkers confirmed the mechanism against the code — not reproduced at
  runtime."* That field is already the unverified one, which is exactly the right strength. Phase 4
  reads it to start its evidence ladder at layer 3 instead of layer 1, and to know it must still run
  layers 3–5. Without the line the issue is indistinguishable from a hand-written one and the
  adversarial verification is spent twice.
- Architecture → `dev:create-epic` for the drift, or an ADR when it is a decision rather than work.
  **`dev:docs` owns ADRs** — their numbering and location are its rules, not this skill's. Hand it
  over rather than inventing a path.
- **Touched files go in `## Scope`** — `dev:create-bug`'s existing field for *where it bites*. Do
  not invent a `touches:` field: per `GUIDE.md`, a per-type template field belongs to the
  `dev:create-*` member, not to a caller asserting one from outside.
- **Two issues touching one file are conflicting, not blocking.** Say so in both `## Scope` lines
  and let whoever starts second rebase. Blocking is a real dependency — B's fix does not apply until
  A's has landed — and it is directional, which "same file" never tells you. Calling every shared
  file a block serialises a codebase behind its utils module, the opposite of what this list is for.
- **Set a priority label on each filed issue, from the cost ranking.** `dev:kanban` Phase 5 orders
  the backlog by `P1 → P2 → P3`, then slice, then oldest `updatedAt` — ten issues filed the same
  minute share a timestamp, so without labels the order it shows is arbitrary and this phase's
  ranking dies in the report. If the repo has no priority labels, say so: the ranking then lives
  only here.
- **File at most 10 per run, and name what was held.** `dev:kanban` shows the top 2–3 of BACKLOG, so
  ten is already more board than anyone reads at once; thirty is a backlog that gets skipped
  wholesale. Rank by cost-if-it-bites — say which one you ranked first and why, so it is a claim
  that can be argued with. The rest stay in the report, which is why the report is written first.
- **Bugs outrank opportunities inside the ten** unless the developer says otherwise. A tracker that
  fills with improvements while defects wait is one nobody trusts.

## Never

- **Never implement.** Not a fix, not a rename, not an obvious one-liner. Suggest only.
- **Never file a PLAUSIBLE finding**, and never file without asking.
- **Never file an opportunity as a bug** (Phase 1). It makes the board lie about how broken the app
  is, and `dev:kanban` ranks from that board.
- **Never file an opportunity whose gain has no number, unit or count** — that is a preference.
- **Never show the fix before asking for theirs.** Phase 8 is worthless the instant an answer is
  visible; anchoring is not undone by asking politely afterwards.
- **Never invent a flow, a finding, or a count.** An honest *"this flow is clean"* is a result;
  `shared/entry.md`'s *a result is not a claim* applies to every number in the report.
- **Never recommend an architecture the codebase does not already mostly use.**
- **Never run against a repo other than the resolved one.**

## Next — ask, never stop flat

`shared/entry.md` → *Never end silently* applies here as to every sibling.

Report written → **walk the findings through (Phase 8)** → offer the filing, naming the branch it
would cut. Filed → name the first issue by cost and hand to `/dev #N`. **Nothing found → say so
plainly, name what was covered and what was not, and offer `dev:kanban`** — a clean run is a real
answer, but the board may still hold work, and stopping at "nothing" makes the developer remember
there is somewhere else to look.

## Scar tissue

**2026-09-10 — renamed from `dev:survey` and given a third hunt.** The rename kept every rule; the
addition is `--opportunities`. Two things were decided at the rename and are worth stating because
they could quietly erode:

- **Opportunities go through Phase 5 exactly as bugs do.** The temptation is to treat an improvement
  as low-risk and skip verification. It is the opposite: a bug that turns out not to exist wastes a
  close, while an "optimisation" that moves a cost rather than removing it wastes a whole branch and
  looks successful.
- **The evidence standard for an opportunity is a number, not a narrative.** Without it the hunt
  degenerates into taste, and taste filed into a tracker is indistinguishable from work.

**Undated, therefore unproven:** the opportunities hunt has not been run against a real codebase,
so its finding rate, its checker cost and the bugs-outrank-opportunities rule in Phase 9 are all
designed rather than observed.
