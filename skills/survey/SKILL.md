---
name: survey
description: >
  Reads an EXISTING app's flows and reports what is wrong with it — real bugs, and the architectural
  drift between the patterns actually in use — then files the confirmed ones. It suggests and never
  implements: no fix, no refactor, no rewrite.
  Every finding is adversarially verified against the code before it can be filed, because a tracker
  full of plausible-but-wrong issues is worse than an empty one and `dev:issues` will rank it either
  way. Unverified findings are held in the report with the reason, never filed.
  Writes `docs/survey/<date>.md` first; filing to GitHub is a separate confirmed step. Fans out one
  surveyor per flow, and shapes what it files so several issues can be started at once.
  Trigger on: "what's wrong with this app", "find the bugs in this codebase", "survey the code",
  "audit the architecture", "is this MVVM or clean", "the architecture is inconsistent",
  "what should we fix", "review the whole app".
allowed-tools: [git, gh, rg, grep, Read, Write, Agent]   # Read: every verdict is read-backed. Write: the report. Agent: one surveyor per flow.
---

# survey — read the app, report what is wrong, file the confirmed

A **tool**, not a phase, and it sits **upstream of Phase 0**. `dev:issues` renders the board;
nothing stocked it. Every door from Phase 0 on assumes you already know what is wrong — this is the
one that finds out.

**It suggests. It never implements.** No fix, no refactor, no rewrite, not even an obvious one.
The output is a report and, on confirmation, issues. `/dev #N` does the work afterwards.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | every flow it can discover | this |
| A flow name (`checkout`) | that flow only | all |
| `--arch` | Phase 6 only — skip Phases 4 and 5 entirely | both |
| `--bugs` | Phases 4 and 5 only — skip Phase 6 | both |

## Phase 2 — Resolve the repo, then read what is already tracked

`shared/entry.md` for repo resolution — the resolved repo is the boundary, for reading and for
filing.

**Then fetch the open issues before surveying anything.** A survey that files a bug already in the
tracker has made the board worse. One call, as `dev:issues` Phase 3 does it:

```bash
gh issue list --state open --limit 200 --json number,title,labels
```

**A tracker past 200 is truncated, and a truncated dedupe list files duplicates without knowing.**
`dev:issues` states this limit; so does this. If the count comes back at the limit, say the dedupe
is partial and treat every near-match as *possible duplicate* rather than as new.

Match on **the file path a finding names plus its symptom**, not on title similarity — two issues
about `cart.ts` losing state are the same bug under different words, and two about different files
are not the same bug under the same words. When the match is uncertain, file nothing and report it
as **possible duplicate of #N**: a wrong merge hides a real bug, and a wrong split costs one close.

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
same unit `dev:trim` uses, and for the same reason: it has to be small enough that one surveyor's
pass fits one context. Label the results **modules, not flows**; a finding under a module says
*this code is wrong*, a finding under a flow says *a user hits this*, and only the second can be
ranked by cost. Everything downstream reads "flow" as "flow or fallback unit".

## Phase 4 — Fan out, one surveyor per flow

**Skipped under `--arch`.** Otherwise dispatch one agent per flow
(`superpowers:dispatching-parallel-agents`). **One flow per agent, never two.** A whole codebase does not fit one context, and a surveyor that runs out mid-flow does not
announce it — it just returns fewer findings, which reads exactly like a clean flow.

Each surveyor returns, per finding: the symptom, the file and line, the **mechanism** that produces
it, and what it expected instead.

**A finding without a mechanism is a guess.** *"Open a course with 40+ lessons, scroll to lesson 30,
press back"* is a finding; *"navigation seems fragile"* is a feeling. This is `dev:create-bug`'s
`## Steps` standard applied one step earlier, and it is the whole difference between a survey and a
vibe.

## Phase 5 — Verify adversarially, before anything is filed

Every finding gets **two independent checkers, each prompted to refute it**, and each must open the
named file and its callers rather than reasoning from the finding's own text. Two, not one: a
single checker that agrees produces a confirmation indistinguishable from a rubber stamp.

**Checkers never see each other's verdict**, and **disagreement resolves to PLAUSIBLE, never to
CONFIRMED** — the safe verdict is the one that holds the finding out of the tracker, since a wrong
CONFIRMED costs a close and a wrong PLAUSIBLE costs a line in a report.

This is not ceremony: three `/code-review` rounds on this repo in one day returned 15, 15 and 15
findings, and the ones that held up did so because each was checked against the code rather than
against how plausible it sounded.

| Verdict | Meaning | Fate |
|---|---|---|
| **CONFIRMED** | the checker reproduced the reasoning against the code and could not refute it | eligible to file |
| **PLAUSIBLE** | it may be real; the checker could not confirm it from the code alone | **held in the report with the reason**, never filed |
| **REFUTED** | the code does not do what the finding claims | dropped, and say how many were dropped |

**Report the refuted count.** A run that refutes nothing is a run whose checker was agreeing, not
checking — the same tell as `dev:trim`'s "a run that keeps nothing".

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

## Phase 7 — Write the report

**Under a flag, the sections whose source phase was skipped are omitted, never left empty.**
`--arch` skips Phases 4-5, so the report carries ARCHITECTURE only and Phase 8 files no bugs;
`--bugs` skips Phase 6, so there is no ARCHITECTURE section and nothing for Phase 8 to raise as an
epic. An empty CONFIRMED reads as *nothing found*, which is a different and much worse claim than
*not looked for*.

`docs/survey/<YYYY-MM-DD>.md`, or `<date>-2.md` if that file already exists — two runs in one day are usually a
narrowed re-run, and overwriting the wider one loses the held PLAUSIBLE set. The file is the
artifact that makes the run reviewable and re-runnable; filing is a separate step, so nothing
reaches the tracker unread. Create `docs/survey/` if the repo has no `docs/`, and say that you did.

```
# Survey — <repo> — <date>
Flows: <n>, from <where they were declared>       Scope: <all | flow | --arch>

## CONFIRMED (n)          ← eligible to file
- <symptom> · <file:line> · mechanism: <exact steps> · expected: <what should happen>
  touches: <paths>        blocks: <other finding, if same files>

## PLAUSIBLE (n)          ← held, not filed
- <symptom> · why it could not be confirmed from the code

## ARCHITECTURE
Actual: <counts, and how counted>   Recommend: <the majority pattern>   Cost of doing nothing: <…>
- <drift item> → <the move>

## ALREADY TRACKED (n)    Refuted and dropped: <n>
```

## Phase 8 — Offer to file, shaped for parallel work

Ask before filing anything. Then, for the confirmed set:

- Bugs → `dev:create-bug`, one per finding, mechanism carried into `## Steps` intact.
- Architecture → `dev:create-epic` for the drift, or an ADR when it is a decision rather than work.
  **`dev:docs` owns ADRs** — their numbering and location are its rules, not this skill's. Hand it over rather than inventing a path.
- **Every filed issue names the files it touches.** Two issues touching one file are **conflicting,
  not blocking** — say so in both, and let whoever starts second rebase. Blocking is reserved for a
  real dependency: finding B's fix is not applicable until A's has landed. Calling every shared file
  a block would serialise a whole codebase behind its utils module, which is the opposite of what
  this list is for. `dev:issues` Phase 5 orders on real blocks; conflicts are a warning, not an
  order.
- **File at most 10 per run, and name what was held.** `dev:issues` shows the top 2–3 of NEXT, so
  ten is already more board than anyone reads at once; thirty is a backlog that gets skipped
  wholesale. Rank by cost-if-it-bites — say which one you ranked first and why, so it is a claim
  that can be argued with. The rest stay in the report, which is why the report is written first.

## Never

- **Never implement.** Not a fix, not a rename, not an obvious one-liner. Suggest only.
- **Never file a PLAUSIBLE finding**, and never file without asking.
- **Never invent a flow, a finding, or a count.** An honest *"this flow is clean"* is a result;
  `shared/entry.md`'s *a result is not a claim* applies to every number in the report.
- **Never recommend an architecture the codebase does not already mostly use.**
- **Never survey a repo other than the resolved one.**

## Next — ask, never stop flat

Report written → offer the filing. Filed → name the first issue and hand to `/dev #N`.
Nothing found → say so plainly and stop; a clean survey is an answer.
