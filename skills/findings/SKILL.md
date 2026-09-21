---
name: findings
description: >
  Reads an EXISTING app's flows and reports what is wrong with it — real bugs, and the architectural
  drift between the patterns actually in use — then files the confirmed ones. It suggests and never
  implements: no fix, no refactor, no rewrite.
  Every finding is adversarially verified against the code before it can be filed, because a tracker
  full of plausible-but-wrong issues is worse than an empty one and `dev:board` will rank it either
  way. Unverified findings are held in the report with the reason, never filed.
  Writes `docs/findings/<date>.md` first; filing to GitHub is a separate confirmed step. Fans out one
  finder per flow, and shapes what it files so several issues can be started at once.
  Trigger on: "what's wrong with this app", "find the bugs in this codebase", "survey the code",
  "audit the architecture", "is this MVVM or clean", "the architecture is inconsistent",
  "what should we fix", "review the whole app".
allowed-tools: [git, gh, rg, grep, Read, Write, Agent]   # Read: every verdict is read-backed. Write: the report. Agent: one finder per flow.
---

# findings — read the app, report what is wrong, file the confirmed

A **tool**, not a phase, and it sits **upstream of Phase 0**. `dev:board` renders the board;
nothing stocked it. Every door from Phase 0 on assumes you already know what is wrong — this is the
one that finds out.

**It suggests. It never implements.** No fix, no refactor, no rewrite, not even an obvious one.
The output is a report and, on confirmation, issues. `/dev #N` does the work afterwards.

> **Sibling: `dev:ideation`.** This door asks *what does this do that it should not?* — defects and
> architectural drift. That one asks *what does this do adequately that could be materially better?*
> — performance, security and quality opportunities, filed as `enhancement`. They discover the same
> flows and fan out the same way, so **run one, not both, unless you mean to.** Defects first: what
> is broken changes which improvements are worth making. This door is the source of truth for the
> protocol they share — Phases 2, 3, 4, 5 and 8.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | every flow it can discover | this |
| A flow name (`checkout`) | that flow only | all |
| `--arch` | Phase 6 only — skip Phases 4 and 5 entirely | both |
| `--bugs` | Phases 4 and 5 only — skip Phase 6 | both |
| `--plan=decide\|alert` | how the fan-out is approved (Phase 4) | `alert` |
| `--walkthrough=decide\|alert\|skip` | Phase 8 | `alert` |
| `--file=decide\|alert\|skip` | Phase 9 | `alert` |
| `--max-agents=<n>` | the most agents this run may start, finders and checkers together | none |

### The stops are chosen before the run starts (ADR 0043)

This door stops three times: to approve the fan-out, to walk each finding through, and to file. A run
started from Dev Desk — often in the background, where **nobody is there to answer** — is told up front
what each stop does. A run with no stop arguments asks at all three, exactly as before.

| Value | Means |
|---|---|
| `alert` | stop and ask; in the background, end the turn with the question so the app shows **Answer…** |
| `decide` | take the decision this skill's own rules make, **write it and its reason into the report**, and carry on |
| `skip` | do not run that stop at all (not valid for `--plan`) |

**Never ask at a stop whose value is `decide` or `skip`** — not "just to be safe", not once. A run
that asks anyway is a run that hangs in the background.

**`--max-agents` is a wall, not a target.** Plan first (Phase 3 flows, Phase 4 finders, ~2 checkers per
expected finding). If the plan exceeds it, **start nothing** and end with exactly one line, first:

```
Refused: the plan needs <n> agents and the limit is <max>. Narrow the scope (one flow, --bugs or --arch) or raise the limit in Dev Desk → Settings → Execution.
```

Dev Desk shows a run that ends with `Refused:` as failed, with that line. Never narrow silently to fit.
If checkers alone would push a started run past the limit, stop spending, write the report with what
was verified, and name what was left unverified — the limit still holds.

**Every run is from scratch.** A report that is deleted, only in git history, or older than today is
never evidence: every finding in this run is found and verified in this run. Earlier reports are read
only by Phase 2's dedupe, as *what was already tracked*.

## Phase 2 — Resolve the repo, then read what is already tracked

Read `~/.claude/.dev-root/shared/entry.md` — **the absolute path, because this skill runs
inside somebody else's repo**, where a bare `shared/entry.md` resolves to a file that does not
exist. The resolved repo is the boundary, for reading, for writing and for filing.

Also read `~/.claude/.dev-root/shared/pipeline/00-principles.md` → **Guiding Principles
and Right-Size the Process**, and `~/.claude/.dev-root/shared/pipeline/18-output-and-universal-rules.md` → **Universal Rules**. Right-Size is not optional here despite this being a tool: it owns the
fan-out rule, and Phases 4 and 5 are the largest fan-out in the family.

**A findings run that files a bug already in the tracker has made the board worse.** Dedupe runs at
Phase 9, once findings name files — **searched per path, never as a bulk list**:

```bash
gh issue list --repo <owner/repo> --state open --search "<path> in:title,body" \
  --json number,title,body
```

**Why per-path and not `--limit 200`.** The match key is the file path plus the symptom, and both
live in the **body** — which `--json number,title,labels` does not return at all, so a bulk list
cannot dedupe even in principle. Searching also has no 200-issue ceiling to silently truncate
behind, which `shared/entry.md`'s *scope limiter* rule forbids relying on. `--repo` is explicit
because the repo being read is the resolved one, not whatever `cwd` points at.

**If `gh` errors or the repo has Issues disabled, say so and stop.** An empty result and a failed
query must never render the same — `dev:board` Phase 3's rule, and the reason it exists is that a
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

**Read `docs/flows.md` first when the repo has one** — the project's flow list, shared with `dev:arch` and the
Diagrams screen (ADR 0047): one bullet per flow, `- <Name> — also: <other names>`. Keep the flow ids in your
*Per flow* table (`build-create`), and make sure each one is on the list — as a flow's name or in its `also:` —
adding it where it belongs. That is what keeps the same flow from being three rows under three names.

**Print the flow list and its source before reading any of it.** A flow you cannot point at a declaration
for is one you invented, and every finding under it inherits that.

If nothing declares flows, say so and fall back to **one directory below the source root** — the
same unit `dev:comment-budget` uses, and for the same reason: it has to be small enough that one finder's
pass fits one context.

**A nested project is not a flow of THIS one.** A tracked directory carrying its own manifest —
`package.json`, `Package.swift`, `build.gradle`, `pyproject.toml`, `ARCHITECTURE.md`,
`PROJECT_MAP.md` — is a separate project: a test fixture, an example app, a vendored sample. **Print
it as excluded, with the manifest that identified it**, and read it only if asked by name.

> **2026-09-10, found by the verification gate.** This family's own repo tracks
> `tests/e2e-project/`, a complete Next.js app with its own `package.json` and
> `ARCHITECTURE.md`, used to exercise the doors. `git ls-files` includes it and
> `src/app/status/page.tsx` is a genuine declared route — so an unguarded run reports a **fixture's**
> flow as this repo's, and every finding under it is real code that nobody ships. Excluding build
> output by construction does not exclude a whole application checked in as a test.

**Enumerate with `git ls-files`, never with a directory walk.** Tracked files only means build
output, vendored trees and anything `.gitignore`d are excluded *by construction* — `node_modules`,
`dist`, `.next`, `Pods`, `target` — rather than by a blocklist that needs a new entry per ecosystem
forever. A finder auditing compiled assets burns a whole agent to find nothing. Label the results **modules, not flows**; a finding under a module says
*this code is wrong*, a finding under a flow says *a user hits this*, and only the second can be
ranked by cost. Everything downstream reads "flow" as "flow or fallback unit".

## Phase 4 — Fan out, one finder per flow

**Skipped under `--arch`.** Otherwise dispatch one agent per flow
(`superpowers:dispatching-parallel-agents`). **One flow per agent, never two.** A whole codebase does
not fit one context, and a finder that runs out mid-flow does not announce it — it just returns
fewer findings, which reads exactly like a clean flow.

**Live progress is `/tasks`, not something this skill prints.** The harness already shows every
running subagent with its elapsed time and token count, live and continuously — a snapshot printed
between dispatches would be strictly worse. **Name the flow in each agent's task description**
(`findings: checkout`) so that view is readable at a glance instead of six identical rows, and point
the developer at `/tasks` when you declare the fan-out.

**What `/tasks` cannot show, and this skill must record**, per finder as it returns:

- **the finding count** — `/tasks` knows an agent finished, not what it concluded
- **done-with-nothing vs died** — both leave no findings, and they mean opposite things. A crashed
  finder read as a clean flow is the failure mode this whole phase exists to prevent
- **duration, tokens and tool calls at completion** — `/tasks` shows them live and they are gone
  once the run ends; Phase 7 reconciles the estimate against them, and unrecorded, the estimate can
  never get better

**Declare the fan-out before spending it** (Right-Size, `shared/pipeline.md`): *"18 flows → 18
finders, then ~2 checkers per finding."* This is the family's largest fan-out — 60 routes is 60
finders and can be 300 checkers. **What happens next is `--plan`:**

- **`alert`** (the default) — ask *"Go, or narrow it?"* and wait. **Above 12 flows, propose a narrowing
  first** rather than asking them to approve a number they have no way to price.
- **`decide`** — the developer approved the run by starting it with a limit. Check the plan against
  `--max-agents` (refuse as above if it is over), then go without asking, and record in `## COST` which
  flows were chosen and why, and the planned agent count.

**Split flows finely enough for one finder each.** A flow is one thing a user does — load and grant
access, search, open a detail, favourite — not one screen. Two finders each covering half an app will
return fewer findings without saying so.

Each finder returns, per finding: the symptom, the file and line, the **mechanism** that produces
it, and what it expected instead.

**A finding without a mechanism is a guess.** *"Open a course with 40+ lessons, scroll to lesson 30,
press back"* is a finding; *"navigation seems fragile"* is a feeling. This is `dev:create-bug`'s
`## Steps` standard applied one step earlier, and it is the whole difference between a findings run and a
vibe.

**Each finder walks its flow as a user, with realistic inputs — not only as a reader of the code.**
Its prompt names them: the formats people type (a local vs international phone number), the fields
people leave empty (a birthday with no year, a contact with no name), and first-run paths (a denied
permission on a fresh install). A code-first pass finds smells; behaviour bugs have none.
Observed 2026-09-22: a code-first audit of a contacts app found concurrency and duplication and
missed a search that could not find `054…` for `+972 54…`; per-flow finders prompted with inputs
found it, a yearless birthday rendering as year 1, and a denial screen showing "Something Went Wrong".
**Every CONFIRMED verdict is `read in code`**, never `reproduced at runtime`, unless a checker ran it —
the report says which, per `shared/entry.md` → *A written claim carries its evidence*.

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
same way as finders, and **stop and re-ask if the checker count passes twice the declared
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

## Phase 6 — The architecture pass — count before recommending

**Skipped under `--bugs`.** Separate from the bug hunt, and it produces **an ADR or an epic, never
a pile of bug issues**.

1. **Name what is actually there, with counts.** *"11 screens: 7 MVVM, 3 MVC, 1 TCA"* — measured by
   reading them, and say how you counted.
2. **Recommend the pattern the codebase already mostly is.** Unification means moving the minority
   to the majority. Recommending TCA to a codebase that is 70% MVVM is a **rewrite wearing the word
   unify**, and it will not happen.
3. **List the drift as individual moves**, each one a slice someone could take.
4. **Never recommend a rewrite**, and never recommend a pattern absent from the codebase unless the
   developer asks for one. If the honest answer is *"it is already consistent"*, that is the finding.

State the cost of doing nothing, or the recommendation is a preference.

## Phase 7 — Shape tickets and groups, then write the report

### 7a — One ticket per fix, and every shared line of code named

A report row is read as a ticket — by a person and by Dev Desk, which lists every row. Twenty-six rows
for eight fixes is a board nobody starts. So before writing, shape the verified findings:

- **Fold findings that are one fix into one entry.** Same fix site and one change fixes all of them —
  a defect and the drift item on the same line (`print` on the search path, and "print where the code
  uses os.Logger"), or three symptoms of one matcher. The entry keeps every mechanism and names them
  in `cases:`. Sharing a *file* is not a fold; sharing the *fix* is.
- **Name the code, not only the file.** `touches:` lists `File.swift › function()` — the functions,
  properties or types the fix changes. A file alone cannot tell two tickets that edit different
  functions (parallel, git merges them cleanly) from two that rewrite the same one (they must wait).
- **Write the direction.** `needs: <id> — <why>` when this fix does not apply until that one has
  landed: it edits code the other moves, or reads state the other introduces. Directional, and never
  inferred from a shared file alone.
- **Write every meeting.** `shares: <id> <File › code> — different code, parallel` or `— same code,
  after <id>`. Both tickets carry the line, so whichever starts second knows.
- **Held cases stay held, with their criticality.** A PLAUSIBLE case whose fix site is a confirmed
  entry's is listed on that entry as `held: <id> <case> — <high|low>: <what it breaks>` — high only
  when it breaks something the README or the app's audience relies on. It is never folded into a
  CONFIRMED entry: the developer decides at Phase 8, and a yes turns it into a case there.

### 7b — Group what must ship together

A **group** is tickets that must reach the base branch together to make one outcome true. It gets one
branch, `group/<slug>`; its tickets merge into that branch as their agents finish, and the group merges
once, with one review. Tests, in order of strength:

1. **A `needs` chain.** B needs C → same group. Half of it on the base branch is a broken state.
2. **One user flow across layers** — the data, logic and UI tickets of one screen or behaviour.
3. **One drift epic** from Phase 6.

**Not a group:** a shared file (that is `shares:`), a shared root cause (that is one ticket), a shared
type or severity. **Hotfix and security tickets are never grouped** — they go to the base branch alone,
first, and open groups pull the base branch in afterwards.

Order inside a group runs **data → logic → UI → tests**, then by `needs`. Size follows the outcome,
not a number; a group large enough to hide its own order is split into subgroups, one level deep.
Everything ungrouped runs on its own branch: it starts now when its `shares` are all different code,
and otherwise waits for the ticket it shares code with and branches from that ticket's work.

Every entry carries `type:` — **Data flow** (state, threading, source of truth), **Logic** (the rules
are wrong), **UI** (renders wrong over right data), **Architecture** (structure, no behaviour change) or
**Tests** — and `id:`, the reference every `needs`, `shares`, `held` and group line uses.

### 7c — Write the report

**Under a flag, the sections whose source phase was skipped are omitted, never left empty.**
`--arch` skips Phases 4-5, so the report carries ARCHITECTURE only and Phase 9 files no bugs;
`--bugs` skips Phase 6, so there is no ARCHITECTURE section and nothing for Phase 9 to raise as an
epic. An empty CONFIRMED reads as *nothing found*, which is a different and much worse claim than
*not looked for*.

`docs/findings/<YYYY-MM-DD>.md`, and `<date>-<HHMM>.md` for every later run that day — two runs in one day are usually a
narrowed re-run, and overwriting the wider one loses the held PLAUSIBLE set. The file is the
artifact that makes the run reviewable and re-runnable; filing is a separate step, so nothing
reaches the tracker unread. Create `docs/findings/` if the repo has no `docs/`, and say that you did.
Reports from before this door was renamed from `dev:survey` sit in `docs/survey/`: read both when looking for an
earlier run, and write only to `docs/findings/`.

**Check whether the repo tracks it** — `git check-ignore -q docs/` — and say which answer you got. If
`docs/` is ignored the report is a local working file: still written, still read before anything is
filed, but not in the clone, so the branch-cutting rule above does not apply to it and a reader
should not be sent looking for it in the repo.

**Writing the report is a write, and the write boundary applies** (`shared/entry.md` rule 3): name
`owner/repo`, and **cut a branch in a worktree of its own before creating the file** (`shared/entry.md` rules 3–4) rather than dropping a tracked file onto
whatever branch the developer is standing on. This is the one phase that is not read-only, and it
must not be described as if it were.

```
# Findings — <repo> — <date>
Flows: <n>, from <where they were declared>       Scope: <all | flow | --arch>

## GROUPS (n)
### <id> · <outcome>
branch: group/<slug> · why: <needs chain | one flow across layers | drift epic> — <one line>
1. <entry id> — <title>
2. <entry id> — <title>

## CONFIRMED (n)          ← eligible to file
- <symptom> · <file:line> · mechanism: <exact steps> · expected: <what should happen>
  id: <C1>   type: <Data flow | Logic | UI | Architecture | Tests>   group: <G1 · 2 of 3 | none>
  touches: <File.swift › function(), property>; <Other.swift › Type>
  needs: <id> — <why>                      (one line each; omit when none)
  shares: <id> <File › code> — <different code, parallel | same code, after id>
  cases: <folded finding> · <folded finding>   (omit when one)
  held: <id> <case> — <high|low>: <what it breaks>

## PLAUSIBLE (n)          ← held, not filed
- <symptom> · why it could not be confirmed from the code
  id: <P1>   near: <entry id whose fix site it shares, if any>

## ARCHITECTURE
Actual: <counts, and how counted>   Recommend: <the majority pattern>   Cost of doing nothing: <…>
- <drift item> → <the move>
  id: <A1>   type: Architecture   group: <G3 · 1 of 4 | none>   touches / needs / shares as above

## ALREADY TRACKED (n)
<finding id> → #N · merged (same fix site) | related | register row <r>

## NET
opened <n> · merged into existing <n> · placed in a milestone <n> · unplaced <n> · open issues <before> → <after>

## COST
Declared <shape>  ·  Actual <agents, wall, tokens, calls>  ·  Overrun <what and why, or none>
<per-flow table: findings, duration, tokens, calls — FAILED rows included>
```

**Every verified finding is an entry with an `id:`, and its fate is written in exactly one other place.**
A finding that merges into an open issue keeps its entry under CONFIRMED (or the drift list) and gets one
`ALREADY TRACKED` line — `<id> → #N · merged` — never a free-form bullet of its own: Dev Desk reads every
bullet in CONFIRMED as new work and every `ALREADY TRACKED` merge and `## FILED` row as done, keyed by `id`.
The FILED table's first two columns are always `id | #issue`. **The entry's first line is its title** — one
sentence, no file paths; paths go on the indented lines. Scar, 2026-09-19: a merged finding written as an
un-id'd bullet and two drift items with paths in their titles rendered as three raw report lines, and a
FILED table Dev Desk never read left ten filed findings saying "not filed yet".

**The field lines are indented under their entry, one `key:` per field or several separated by three
spaces**, and `id:` is required on every entry once any entry has one — Dev Desk resolves `needs`,
`shares`, `held` and the GROUPS lists through it, and an unresolvable reference is shown as one.

**A finding's line may be bulleted (`-`) or numbered (`1.`)** — numbering a ranked CONFIRMED list is
expected, and the section heading is what decides a verdict, not the marker. A drift list keeps its
`**Drift — CONFIRMED**` / `**Drift — PLAUSIBLE**` heading inside `## ARCHITECTURE`: those bold lines
are what separate the section's verdicts from its prose, for a human and for Dev Desk alike.

### The `## COST` section — reconcile the estimate, or it never improves

Right-Size makes this skill declare a fan-out before spending it. Declaring without ever reporting
the actual is half a rule: the next run's estimate is then guesswork with a track record it cannot
read.

```
## COST
Declared   6 finders + ~2 checkers per finding  (floor: 12 agents)
Actual     6 finders + 14 checkers = 20 agents · 7m04s wall · 412k tokens · 231 tool calls
Overrun    +2 agents — one flow returned 5 findings where the floor assumed 2

Per flow          findings   duration   tokens   calls
  auth                   2      1m12s      38k      14
  checkout               0        52s      21k       9
  account                1      1m41s      47k      19
  admin                  5      2m03s      61k      27   ← the overrun
  build              FAILED     0m14s       3k       2   ← died, NOT clean
  export                 0      1m08s      29k      11
```

- **A failed finder is a row, not a silence.** `FAILED` and `0 findings` mean opposite things and
  a missing row means neither. Whatever a dead flow leaves behind, it is not evidence of clean code.
- **Wall time is not the sum of the durations** when agents run concurrently. Report both: the sum
  is what it cost, the wall is what it felt like.
- **Run inline with no fan-out and this section says so**, with no per-agent figures invented. A
  sequential run has no per-agent data, and a plausible-looking table is worse than its absence.

## Phase 8 — Walk it through, one finding at a time (BEFORE the filing offer)

**`--walkthrough`:** `alert` runs this phase as written. `skip` goes straight to Phase 9. `decide` asks
nothing: for each confirmed entry, write your handling and its `alternatives considered` / `rejected:`
line under the entry in the report, where the developer reads it later.

**The developer's stated purpose for this gate: build their own model of the system, not receive
one.** A finding they can restate is worth more than three they approved. So this phase is not a
summary — it asks first and answers second, on **every** confirmed finding.

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

**`just do it` skips the current finding. `just do it all` skips the rest of the phase.** No
re-asking, no friction, no second attempt at persuasion — and the bulk form matters here more than
anywhere: this is the family's widest fan-out, so a 20-finding run without it costs 20 separate
escapes, which is the ceremony GUIDE principle 4 refuses. `shared/pipeline.md` Phase 5 gives the
whole-step scope by default because it gates ONE plan; this phase gates N findings, so it needs both. A gate that argues with a skip is a gate that gets routed around.

**Never batch.** One finding, one answer, one diff. A list of five questions gets one answer about
the last one.

---

## Phase 9 — Offer to file, shaped for parallel work

**`--file`:** `alert` asks before filing anything, as written. `skip` files nothing — the report is the
result, and Dev Desk files from its Findings screen. `decide` files the confirmed set by the rules below
without asking, and lists what it filed at the end of the report.

Ask before filing anything (under `alert`). Then, for the confirmed set:

- **Merge before you file** — `~/.claude/.dev-root/shared/duplicates.md`, applied per confirmed
  finding against Phase 2's per-path search and recorded in `## ALREADY TRACKED`. **One addition at
  this door:** a finding that matches a row of the repo's decided-but-not-built register (e.g.
  `docs/06-roadmap.md`) is filed and the row is named in the report, so `dev:docs` re-points it — this
  door does not edit docs.
- Bugs → `dev:create-bug`, one per finding, mechanism carried into `## Steps` intact.
- **Name this run in `## Suspected`, and say what the verdict does NOT cover:** *"found by
  `dev:findings` <date>; two checkers confirmed the mechanism against the code — not reproduced at
  runtime."* That field is already the unverified one, which is exactly the right strength. Phase 4
  reads it to start its evidence ladder at layer 3 instead of layer 1, and to know it must still run
  layers 3–5. Without the line the issue is indistinguishable from a hand-written one and the
  adversarial verification is spent twice.
- Architecture → `dev:create-epic` for the drift, or an ADR when it is a decision rather than work.
  **`dev:docs` owns ADRs** — their numbering and location are its rules, not this skill's. Hand it over rather than inventing a path.
- **The coordination lines go in `## Scope`** — `dev:create-bug`'s existing field for *where it
  bites*: `touches`, `needs`, `shares` and `group`, verbatim from the report. Do not invent a
  template field: per `docs/guide/CONTRIBUTING.md`, a per-type field belongs to the `dev:create-*`
  member, not to a caller asserting one from outside.
- **A shared file is not a block; shared code is an order.** `shares … different code` runs in
  parallel. `shares … same code, after <id>` and `needs` wait, and the one that waits branches from
  the work it waited for (`shared/pipeline/04-phase-03-branch-naming.md` → *Shared code*). Calling
  every shared file a block serialises a codebase behind its utils module; calling nothing a block
  sends two agents to rewrite one function and leaves the merge to whoever finishes second.
- **A group files as a `dev:create-epic` parent with its tickets as sub-issues**, in group order.
  This is the one caller that files an epic's slices itself (ADR 0040): Phases 4–5 already
  investigated each one against the code, which is what `dev:create-epic` waits for Phase 5 to do.
  **With no tracker** (ADR 0027) the group is a parent entry in `docs/backlog/` and each ticket's
  entry carries `group:`, `order:`, `needs:` and `touches:` in its header.
- **Starting over adopts what already started.** Before filing, match every entry against open
  issues and `docs/backlog/` by key and title. A ticket already in progress or done is adopted — its
  group and order are recorded on it — never filed a second time.
- **Set a priority label on each filed issue, from the cost ranking.** `dev:board` Phase 5 orders
  NEXT by `P1 → P2 → P3`, then slice, then oldest `updatedAt` — ten issues filed the same minute
  share a timestamp, so without labels the order it shows is arbitrary and this phase's ranking dies
  in the report. If the repo has no priority labels, say so: the ranking then lives only here.
- **Set `impact:` and `complexity:` from the same ranking**: impact is what the defect costs while
  it stands, complexity the cost of fixing it. Both are proposals the developer corrects
  (`docs/guide/WORKFLOW.md` → *Rating an issue*), and a label the repo lacks is offered, never
  created silently.
- **Every filed issue lands in a milestone, or is named as unplaced** (`duplicates.md` step 3). Read the open milestones
  (`gh api repos/<o>/<r>/milestones --jq '.[] | "\(.number) \(.title) — \(.description)"'`) and assign
  each filed issue whose milestone's *because* covers it. The rest go in the report under
  `unplaced:` with one line each, and the run ends by offering `dev:roadmap` for them. **Do not create
  milestones here** — themes are `dev:roadmap`'s decision, with its per-theme yes. Scar, 2026-09-17:
  10 bugs filed, 0 in a milestone, while 3 open milestones covered 5 of them.
- **File at most 10 top-level items per run — a group counts as one — and name what was held.**
  `dev:board` shows the top 2–3 of BACKLOG, so ten is already more board than anyone reads at once;
  thirty is a backlog that gets skipped wholesale. Rank by cost-if-it-bites — say which one you ranked first and why, so it is a claim
  that can be argued with. The rest stay in the report, which is why the report is written first.

## Never

- **Never implement.** Not a fix, not a rename, not an obvious one-liner. Suggest only.
- **Never file a PLAUSIBLE finding**, and never file without asking.
- **Never show the fix before asking for theirs.** Phase 8 is worthless the instant an answer is
  visible; anchoring is not undone by asking politely afterwards.
- **Never invent a flow, a finding, or a count.** An honest *"this flow is clean"* is a result;
  `shared/entry.md`'s *a result is not a claim* applies to every number in the report.
- **Never recommend an architecture the codebase does not already mostly use.**
- **Never read a repo other than the resolved one.**

## Next — ask, never stop flat

`shared/entry.md` → *Never end silently* applies here as to every sibling.

Under `decide` or `skip` at every stop, end with the report's path and what it holds — never a question.
Otherwise: report written → **walk the findings through (Phase 8)** → offer the filing, naming the branch it would cut. Filed → name the first issue by
cost and hand to `/dev #N`. **Nothing found → say so plainly, name what was covered and what was
not, and offer `dev:board`** — a clean findings run is a real answer, but the board may still hold work,
and stopping at "nothing" makes the developer remember there is somewhere else to look.
