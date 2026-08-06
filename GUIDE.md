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

Not ready to build it yet? `/dev:create-bug`, `/dev:create-issue` and `/dev:create-epic` file it into
the tracker instead — one turn, no branch, no work — and hand you the number to run `/dev #N` on
whenever you are ready.

## It will ask you two things

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

### 2. The go-ahead — *"should we build this at all?"*

Before writing code it explains, in plain language, what it intends to do and why, and waits.
This is **Phase 5**, and it stops however the run was started.

**Use it.** This is the cheapest moment to say *"actually, no"* or *"not like that"*. Disagreeing
here costs a sentence; disagreeing after Phase 9 costs the branch.

## It runs straight through — and stops at four moments

It never asks *"shall I continue?"* between phases. It reports what each one did and moves on. But
these four are decisions, not steps, and it always stops at them:

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
0     file it — only from /dev:create-*, never inside a /dev run
1–2   load project context, detect the stack
3     name the branch (cut at the first write, not before)
4     investigate — for a bug: reproduce it BEFORE theorising
5     ── DISCUSS ── ask you ── (and SPLIT it here, if it's several tasks) ──
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
| *"file a bug"* / *"log this"* | `/dev:create-bug` — drafts the report, files it, does **not** fix it |
| *"file an issue"* / *"capture this"* | `/dev:create-issue` |
| *"this is a big one"* / *"file an epic"* | `/dev:create-epic` — files the **parent only** |
| *"verify this branch"* / *"does this actually work?"* | `/dev:verify` — builds the evidence table, drives the app |
| *"are the docs updated?"* | `/dev:docs` — checks ADRs and PROJECT_MAP against the diff |
| *"open a PR"* / *"merge to staging"* | `/dev:pre-prod` |
| *"changes requested"* + a PR link | `/dev:review` |
| *"promote to prod"* | `/dev:prod` |
| *"run the app"* / *"launch on simulator"* | `/dev:launch` |
| *"kill the dev server"* / *"free the port"* | `/dev:launch-kill` — stops what `launch` started, in this worktree only |
| *"screenshot the app"* / *"app store screenshots"* | `/dev:shots` — captures iOS/Android/web; drives the project's own suite when it has one |

**Starting mid-pipeline never leaves you stranded.** Whichever one you invoke, it finishes by naming
the next phase, what it would do and where it ends — then asks whether to continue. You do not have
to remember what comes after Phase 12, or that it is called `/dev:pre-prod`. Say *"yes"* and it
carries on; say nothing and it stops there, having told you what it stopped short of.

## Six things that will confuse you the first time

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
6. **Every PR gets a `## PIPELINE` section**, and the interesting line is `Skipped:`. It says which
   phases were skipped *and why*. Read that line before the code — an unconvincing reason there is
   the cheapest bug you will ever catch.

## If something goes wrong

- **It is doing too much** → *"light tier"*
- **It is moving too fast to follow** → *"slow down"* / *"ask me between phases"*, honoured for the
  rest of the run. It will never offer this — running through is the default and stays that way
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

> **The date is the marker, and its ABSENCE is information.** A rule carrying a date was paid for
> with a real failure. A rule without one was *reasoned* into existence — plausible, untested, and
> the first thing to suspect when the pipeline fights you. When friction appears, check the
> undated rules before the dated ones; when pruning, they are the cheap cut. Most of Phase 0 and
> the epic decomposition are undated as of 2026-08-04: they are designs, not scars.

**2. A gate is only real if it produces an artifact.** Phase 12 works because its output is a
required `## DOCS` section in the PR — its absence is visible. Gates that produce only a
conversation get skipped and nobody notices. **When adding a gate, ask what it leaves behind.**
`## PIPELINE` is the same idea applied to the phases that produce nothing of their own: it does not
make them leave artifacts, it makes *skipping* them leave one.

**3. Phase 11 is the seam.** Phases 1–10 pass *reasoning*, which exists only in the conversation
that produced it. Phases 11–16 pass *artifacts* — a branch, a diff, a PR number. That is why the
standalone members start at 11 and not earlier, and why an epic cannot resume mid-plan.

**4. Ceremony is the failure mode, not sloppiness.** *A slow pipeline that gets skipped protects
nothing.* Every addition must earn the tier it lands in. Prefer conditional over mandatory.

> **Budget: `shared/pipeline.md` stays under 950 lines** (938 at 2026-08-04). Not a style
> preference — attention per rule falls as the file grows, and a rule nobody reaches is worth less
> than no rule. At the ceiling, an addition is only allowed with a deletion in the same commit;
> `wc -l shared/pipeline.md` before you write. The number is deliberately close to current: this
> file grew 593 → 938 without ever losing a rule, and an unstated ceiling is not a ceiling.

**5. Decisions are not steps.** Automation may skip asking between mechanical stages. It may never
skip a judgment — building, architecture, merging, promoting.

## Where to extend

| Change | Edit |
|---|---|
| Behaviour of any phase | `shared/pipeline.md` — **once**; all 7 entry points read it |
| A stack-specific addition | `shared/pipeline-{web,ios,android,kmp}.md` — these overlay Phases 10, 11, 14 only |
| Branch/environment resolution | `shared/entry.md` |
| A new standalone member | `skills/<name>/SKILL.md` + a row in both family tables. **Only worth it for Phase 0 or a phase ≥ 11** — the rest pass reasoning, which cannot be handed over |
| A new **tool** (no phase) | Same, but it points at another tool rather than at `pipeline.md` — `launch-kill` reads `launch`'s Phase 2 for discovery. The no-copy rule is the same rule |
| A per-type issue template | the `dev:create-*` member itself — templates are the only thing those three doors hold |
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
4. **Say what it replaces — and now you can prove it.** The pipeline grew 593 → 823 lines without
   ever losing a rule, because deletion was never safe: you cannot remove on a hunch what was added
   after an incident. `## PIPELINE`'s `Gates:` line is what makes it safe. Query the history —

   ```bash
   gh pr list --state merged --limit 100 --json body -q '.[].body' | grep '^Gates:'
   ```

   — and a gate that has read `clean` across twenty PRs is a rule you can retire with evidence, not
   nerve. **Every addition names its deletion**, justified either by that query or by pointing at
   where the rule is already written. An addition that removes nothing pays a permanent tax on every
   future task.

## Known gaps

Honest, as of 2026-08-04:

- **Epic support is new and unexercised (2026-08-04).** The design: file the parent with
  `/dev:create-epic`, split it at Phase 5 into real sub-issues, run `/dev #child` per slice — the
  pipeline stays task-shaped and the sub-issue list is the queue. Never run end to end.
- **No rollback.** It runs 1 → 16 and stops. Nothing answers *"prod is broken, now what."*
- **New-project path barely tested.** The `ARCHITECTURE.md`-absent branch and both MASTER_PROMPTs
  have never run.
- **The gate log has a mechanism but no data.** `## PIPELINE`'s `Gates:` line was added 2026-08-04
  to fix this; until ~20 PRs carry it, pruning is still guesswork. It is also self-reported — a run
  that skips a phase *and* omits it from `Skipped:` is invisible, same as before. This buys
  visibility, not enforcement.
- **`dev:pre-prod`, `dev:review`, `dev:prod` unexercised.**
- **Enforcement is part mechanical as of 2026-08-05.** ~5 of 17 phases produce a durable artifact;
  the rest depend on the reader complying, and `## PIPELINE` / `## DOCS` are self-reported — a run
  that skips a phase *and* omits it from `Skipped:` is still invisible. Four hooks in `hooks/` now
  make Phases 1, 3, 12, 14 and 16 — plus Phase 11's teardown rule, though not its checklist —
  mechanical **where they touch a tool call**. That qualifier is the whole limit: a hook checks
  presence of state at a tool boundary, so Phases 4–8 are unreachable by construction, on the same
  seam that gives them no `dev-*` door. Pipe-tested only, **zero real runs**; `hooks/README.md`
  separates the three dated fixes from the undated design. A GitHub Actions check also exists at
  `ci/pr-gates.yml`, deliberately **not installed** — `hooks/pr-gates.sh` supersedes it locally
  (earlier, no infra, no false failures on this repo's own PRs) and it should be deleted once ~10
  real PRs carry `fired.log` evidence, not before.
