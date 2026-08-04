# Using the dev skill

Two halves. **Part 1** is for your first runs — what to type, what it will ask, what to answer.
**Part 2** is for changing it.

---
---

# Part 1 — Your first runs

## What this is

A workflow that takes a bug or a feature from *"what should this do?"* to production, stopping at
the places where skipping costs you something real. It is not a code generator with extra steps —
its whole value is the **gates**: the moments it refuses to move on.

## Start here

There is one command you need:

```
/dev <issue number, issue URL, or a plain description>
```

```
/dev #496
/dev https://github.com/you/repo/issues/496
/dev the course list forgets scroll position when you come back
/dev fix this bug: lectures index shows stale titles after a rename
```

You do not have to type the slash command. Saying *"work on issue 496"* or *"fix this bug: …"*
starts it too.

**That is the whole start.** Everything below is what happens next.

## It will ask you three things

Answer these and you are running it correctly. There are no other required decisions.

### 1. Tier — how much process this deserves

It proposes one; you can override.

| Tier | Means | Typical |
|---|---|---|
| **Light** | tests + a quick diff read | a copy change, a small fix |
| **Standard** | + one real live check | a multi-file feature |
| **Deep** | full evidence, agent-run checklist, security pass | money, auth, migrations, big refactors |

**If unsure, say nothing** — it defaults light and you can say *"go deeper"* any time. A heavy
process you skip protects nothing.

### 2. Mode — how often it stops

| Mode | |
|---|---|
| **Manual** | stops after each phase and waits for you. Slower, and you see everything |
| **Auto** | runs through, stopping only at the real decisions |

**Pick auto once you trust it.** Auto is not "unattended" — four gates stop either way (below).

### 3. The go-ahead — *"should we build this at all?"*

Before writing code it explains, in plain language, what it intends to do and why, and waits.
This is **Phase 5**, and it stops even in auto mode.

**Use it.** This is the cheapest moment to say *"actually, no"* or *"not like that"*. Disagreeing
here costs a sentence; disagreeing after Phase 9 costs the branch.

## The four moments it always stops

Even in auto. These are decisions, not steps — a mode setting is not your consent.

| | Stops to ask |
|---|---|
| **Phase 5** | should this be built, and shaped this way? |
| **Phase 6** | which architecture? (only when there are genuinely different options) |
| **Phase 14** | merge this to pre prod? |
| **Phase 16** | promote to production? |

If it stops anywhere else, something is wrong — an ambiguity, a failed check — and it will say so.

## What happens between the questions

You do not need to memorise these. It announces each as it goes.

```
1–2   load project context, detect the stack
3     name the branch (cut at the first write, not before)
4     investigate — for a bug: reproduce it BEFORE theorising
5     ── DISCUSS ── ask you ─────────────────────
6     architecture options, if there are real ones ── ask you ──
7–8   write the plan, break it into tasks
9     implement — small commits, one logical change each
10    pre-PR checks
11    VERIFY — drives the real app, evidence per row, cleans up after itself
12    DOCS — are the ADRs and PROJECT_MAP still true?      (11 chains into 12 automatically)
13    code review + security pass on Deep
14    ── PR → merge → PRE PROD ── ask you ───────
15    review feedback loops back into 14
16    ── PROMOTE TO PROD ── ask you ─────────────
```

## When you only need one part

The work already exists and you want a single stage:

| Say | Runs |
|---|---|
| *"verify this branch"* / *"does this actually work?"* | `/dev:verify` — builds the evidence table, drives the app |
| *"are the docs updated?"* | `/dev:docs` — checks ADRs and PROJECT_MAP against the diff |
| *"open a PR"* / *"merge to staging"* | `/dev:pre-prod` |
| *"changes requested"* + a PR link | `/dev:review` |
| *"promote to prod"* | `/dev:prod` |
| *"run the app"* / *"launch on simulator"* | `/dev:launch` |

## Five things that will confuse you the first time

1. **It asks before it builds, and it means it.** The pause at Phase 5 is not politeness. Answer
   with what you actually think.
2. **"Deep" does not mean slow.** It means *evidence*, not agents. A Deep rename can finish in
   minutes.
3. **It will tell you when it did not check something.** *"Not reachable — verified by reading the
   route instead"* is an honest row, not a gap. Trust that more than a table of all-green.
4. **Green tests are not the finish line.** Phase 12 exists because a branch once merged with
   perfect tests and no ADR.
5. **It cleans up after itself.** Browsers, emulators and servers it started get killed and
   reported. Anything it did *not* start — your dev server — it will never touch.

## If something goes wrong

- **It is doing too much** → *"light tier"*
- **It is asking too often** → *"auto"*
- **It is going the wrong way** → say so at Phase 5; that is what the gate is for
- **It skipped something** → tell it. That is a bug in the pipeline, and Part 2 is how it gets fixed

---
---

# Part 2 — Changing it

## The five ideas the design turns on

Understand these before editing anything; most "improvements" are re-learning one of them.

**1. Every rule should be scar tissue.** Nearly all of this came from a specific failure — Phase 12
from a branch that merged without its ADR, Phase 16's migrations-first from a schema arriving after
the code that needed it. **A rule with no incident behind it is a guess.** Write the incident into
the rule; that is why so many carry a date.

**2. A gate is only real if it produces an artifact.** Phase 12 works because its output is a
required `## DOCS` section in the PR — its absence is visible. Gates that produce only a
conversation get skipped and nobody notices. **When adding a gate, ask what it leaves behind.**

**3. Phase 11 is the seam.** Phases 1–10 pass *reasoning*, which exists only in the conversation
that produced it. Phases 11–16 pass *artifacts* — a branch, a diff, a PR number. That is why the
standalone members start at 11 and not earlier, and why an epic cannot resume mid-plan.

**4. Ceremony is the failure mode, not sloppiness.** *A slow pipeline that gets skipped protects
nothing.* Every addition must earn the tier it lands in. Prefer conditional over mandatory.

**5. Decisions are not steps.** Automation may skip asking between mechanical stages. It may never
skip a judgment — building, architecture, merging, promoting.

## Where to extend

| Change | Edit |
|---|---|
| Behaviour of any phase | `shared/pipeline.md` — **once**; all 7 entry points read it |
| A stack-specific addition | `shared/pipeline-{web,ios,android,kmp}.md` — these overlay Phases 10, 11, 14 only |
| Branch/environment resolution | `shared/entry.md` |
| A new standalone member | `skills/<name>/SKILL.md` + a row in both family tables. **Only worth it for a phase ≥ 11** |
| Entry routing | `SKILL.md` |

Members are ~60-line doors into the pipeline. **A member that copies pipeline content is a bug** —
they point, never duplicate.

## What not to change without a strong reason

- **The four always-stop gates.** They are the difference between a workflow and an autopilot.
- **Teardown rules.** Never kill a process you did not start. This one protects the developer's own
  session.
- **"Prefer the project's own launch script."** A bare `npm run dev` boots a differently configured
  app, and the difference is invisible until something breaks in a way you cannot reproduce.
- **Phase 12's accuracy rule.** *"Was the doc touched?"* is the easy half. A partial edit passes it
  while leaving the doc lying.

## How to propose a change

**Evidence first — the same standard the pipeline applies to code.**

1. **Name the incident.** What went wrong, on what date, in which run? "It would be better if…"
   is not an input. This whole file's last five fixes came from one real run.
2. **Say what artifact proves it.** If the gate cannot leave evidence behind, it will be skipped.
3. **Say which tier pays for it.** Everything mandatory taxes every task forever.
4. **Say what it replaces.** The pipeline has grown 593 → 823 lines and has never lost a rule. An
   addition that removes nothing needs to be worth its permanent cost.

## Known gaps

Honest, as of 2026-08-04:

- **No epic support.** The pipeline is task-shaped — one branch, one PR, one promotion. Epics
  spanning many tasks, sessions and sub-issues have no representation.
- **No rollback.** It runs 1 → 16 and stops. Nothing answers *"prod is broken, now what."*
- **New-project path barely tested.** The `ARCHITECTURE.md`-absent branch and both MASTER_PROMPTs
  have never run.
- **Nothing measures the gates.** There is no record of which gate has ever caught anything, so
  pruning is guesswork. A per-run log would fix this and enable everything else.
- **`dev:pre-prod`, `dev:review`, `dev:prod` unexercised.**
- **Enforcement is thin.** 3 of 16 phases produce a durable artifact; the rest depend on the reader
  complying. This is the single biggest structural weakness.
