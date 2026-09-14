---
name: insights
description: >
  The FRONT DESK. Answers a question about this codebase from evidence with `file:line` citations,
  routes the question to the door that owns it when it belongs to one, and folds whatever is
  DURABLE into `PROJECT_MAP.md` so the answer does not die with the session.
  It is deliberately small. Asking an agent about a codebase needs no skill; what needs a skill is
  citing the answer, refusing to half-do another door's job, and writing down the part worth
  keeping. `PROJECT_MAP.md` is the pipeline's memory — Phase 1 loads it, Phase 4 skips its
  exploration fan-out when it already covers the area — so every answer folded in makes the next
  run cheaper.
  Trigger on: "what is the architecture of this project", "how does X work here", "where does X
  live", "explain this codebase", "what talks to what", "suggest improvements for code quality",
  "are there any security concerns", "what features could I add next", "update PROJECT_MAP",
  "is PROJECT_MAP current".
allowed-tools: [git, gh, rg, grep, Read, Write]   # Write: PROJECT_MAP.md only.
---

# insights — answer it, route it, keep what lasts

A **tool**, not a phase. Three jobs, in order: **answer**, **route**, **persist**.

**Why this is a door at all.** You are already talking to an agent, so asking about the codebase
needs no skill. What needs one is the discipline around the answer:

1. **cited** — `file:line`, never from memory
2. **routed** — a question another door owns goes *there*, instead of getting a worse version here
3. **kept** — the durable part lands in `PROJECT_MAP.md` instead of dying at session end

Job 3 is the reason it exists. Without it every answer is re-derived from scratch next week.

## Phase 1 — Arguments

| Token | Meaning |
|---|---|
| a question | answer it |
| a greeting / small talk | greet back and invite a question; skip the rest |
| (nothing) | print the seeds below and wait |
| `map` | skip to Phase 5 — audit `PROJECT_MAP.md` against the repo and report drift |

With no argument, offer these four — they are the questions people actually arrive with, and three
of them are really other doors:

```
What is the architecture of this project?      → answered here, and dev:arch can draw it
Suggest improvements for code quality           → dev:ideation
Are there any security concerns?                → dev:ideation --security
What features could I add next?                 → dev:roadmap
```

### Greeting or small talk — stop here

**Check this before Phase 2.** If the argument is a greeting or small talk — *"hello"*, *"hi"*,
*"hey"*, *"thanks"* — and not a question or command about the codebase and not `map`, reply with one
friendly line plus an invitation to ask about the codebase. **Nothing else.**

**Do not resolve the repo, do not read `PROJECT_MAP.md`, and run no later phase.** No *"resolved
owner/repo"*, no *"nothing worth adding to the map"*, no *"no files changed"* — a greeting answered
with a status report is noise. This is not the **(nothing)** case, which still prints the four seeds
above.

## Phase 2 — Resolve the repo

Read `~/.claude/skills/dev/shared/entry.md` — **the absolute path, because this skill runs inside
somebody else's repo.** The resolved repo is the boundary: answer about *that* repo, and Phase 5
writes only into it.

**Load `PROJECT_MAP.md` first if it exists.** It may already answer the question, and if it does,
the honest reply is to quote it and say where it came from — not to re-derive the same thing and
present it as fresh work.

## Phase 3 — Answer from evidence

**Every claim carries a `file:line`.** `shared/entry.md`'s *a result is not a claim* applies to
every sentence here.

- **Never answer from memory of a framework's conventions.** What Next.js usually does is not what
  this repo does. Read it.
- **Enumerate with `git ls-files`**, never a directory walk — tracked files only, so vendored trees
  and build output are excluded by construction rather than by a blocklist.
- **"I could not find it" is an answer.** So is *"three places do this and they disagree — here they
  are."* An invented coherence is the failure mode: a codebase described as tidier than it is sends
  the reader looking for a structure that was never there.
- **Distinguish what the repo DOES from what it SAYS.** A README claim and the code disagreeing is
  itself a finding, and a valuable one — report both with both citations.

## Phase 4 — Route, do not half-do

When the question belongs to another door, **name it and offer the handoff.** Answering it inline
produces a shallower version of work that door does properly, and the developer cannot tell the
difference from here.

| The question | Owner | Why not here |
|---|---|---|
| *draw / diagram / map the system* | `dev:arch` | it produces an evidenced diagram whose nodes point at real code at a real commit |
| *what is broken* | `dev:survey` | findings need two adversarial checkers before anyone acts on them |
| *what could be better / is it secure* | `dev:ideation` | same, plus the gain must carry a number |
| *what should we build next* | `dev:roadmap` | a theme needs traceable evidence and a milestone to live in |
| *what am I working on* | `dev:kanban` | the board is computed from git, not remembered |
| *are the docs current* | `dev:docs` | it owns ADRs and the staleness check |

**A one-paragraph answer plus the offer is right. A half-survey is not.** The line: describing what
you can see is an answer; *judging* it — this is a bug, this is slow, this should be next — is
another door's verdict, and here it would arrive unverified.

## Phase 5 — Fold what is durable into `PROJECT_MAP.md`

The pipeline already names this move — Phase 4: *"Fold anything durable into `PROJECT_MAP.md` (that's
what makes the next task skip this step)"*. This door is that step, available on its own.

### Durable means true of the repo, not of this conversation

| Fold it in | Leave it out |
|---|---|
| a module's responsibility and where it lives | why a test is failing right now |
| a convention the code actually follows | anything about uncommitted or local state |
| a flow's shape, entry point to exit | a restatement of what the code's own docs already say |
| work found incomplete or deliberately deferred | your opinion of the design |
| two places disagreeing, and which is authoritative | a fact one `grep` would give the next reader anyway |

The test: **would this save the next reader a search, next month, on a different branch?** If not,
answering was the whole job.

### The three sections

| Section | Holds |
|---|---|
| `TECH_STACK` | dependencies, tools, conventions in use |
| `SYSTEM_FLOW` | the user journeys and how the code serves them |
| `ORPHANS & PENDING` | incomplete or intentionally deferred work |

**If `PROJECT_MAP.md` is absent, offer to create it** with those three sections and only what this
run actually established — no placeholders, no `TBD`. The pipeline's Phases 1 and 2 both say *"if
absent, create it in Phase 7"*, so an empty repo is expected, not an error. **A map padded with
guesses is worse than no map**, because Phase 4 skips its exploration fan-out when the map claims to
cover an area.

### Writing it is a write

`PROJECT_MAP.md` is a tracked file at the repo root, so `shared/entry.md` rule 3 applies in full:
**name `owner/repo`, and cut a branch** rather than dropping the change onto whatever branch the
developer is standing on. Ask before writing. This is the only file this door ever writes.

### `map` — audit instead of append

Under `insights map`, compare the existing map against the repo and report drift **without writing**:
a `TECH_STACK` entry for a dependency no longer in the manifest, a `SYSTEM_FLOW` describing a
removed route, an `ORPHANS & PENDING` item that has since shipped. Report each with its citation,
then offer the correction.

**A stale map is worse than an absent one** — the same reason `dev:docs` exists. Absent, the
pipeline explores; stale, it skips exploring an area it has been told is covered.

## Phase 6 — Ask next

`shared/entry.md` → *Never end silently*.

Answered and nothing durable → say so plainly: *"nothing here worth adding to the map"* is a real
result. Folded something in → name the section and the branch. Routed → name the door and offer it.
Then ask what they want next.

## Never

- **Never answer from memory.** No `file:line`, no claim.
- **Never invent coherence.** Three implementations that disagree get reported as three.
- **Never half-do another door's job** (Phase 4). Describing is an answer; judging is a verdict.
- **Never write anything but `PROJECT_MAP.md`**, and never without asking.
- **Never pad the map with placeholders or `TBD`.** Phase 4 of the pipeline skips exploration when
  the map claims coverage, so a guess there costs more than a blank.
- **Never fold in what one `grep` would give the next reader anyway.** The map is memory, not an
  index.
- **Never answer about a repo other than the resolved one.**

## Known limits

| | |
|---|---|
| It reads; it does not run the app | A question that needs runtime behaviour goes to `dev:verify` or `dev:launch` |
| No adversarial verification | Answers are cited, not checked by a second reader. A *judgement* needs `dev:survey` or `dev:ideation`, which do check |
| `PROJECT_MAP.md` has no schema beyond three headings | Drift detection under `map` is best-effort and citation-based, not mechanical |

## Scar tissue

**2026-09-10 — written after a redundancy check nearly killed it.** The framework this was modelled
on ships an Insights panel described as *"chat interface for exploring your codebase"*. Ported
literally into an agent CLI, that is a door that does nothing you cannot do by typing — and it was
very nearly dropped for exactly that reason.

What survived the check was the part that is **not** chat: answers are cited, questions that belong
to other doors are routed rather than half-answered, and the durable residue is written down. The
framework needs the panel because it is a desktop app with no chat; this door needs to exist because
**a session ends and `PROJECT_MAP.md` does not.**

**2026-09-10 — the repo that mandates the map does not have one.** `shared/pipeline.md` opens its
Guiding Principles with *"Maintain `PROJECT_MAP.md`"*, and `Live Synchronization` and `Impact
Analysis` both depend on it — yet `dev-skill` itself has no `PROJECT_MAP.md`. A rule stated in three
principles and honoured in none is the reason this door has a Phase 5 at all.

**Undated, therefore unproven:** this door has never been run. The durable/not-durable test, the
`map` drift audit, and whether routing actually stops the half-survey are all designed rather than
observed.
