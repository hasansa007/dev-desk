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

It never asks *"shall I continue?"* between phases. It reports what each one did and moves on. Four
are decisions rather than steps, and it always stops at them — marked `── ask you ──` below. If it
stops anywhere else something is wrong, and it will say what.

You do not need to memorise the rest; it announces each as it goes.

```
0     file it — only from /dev:create-*, never inside a /dev run
1–2   load project context, detect the stack
3     name the branch (cut at the first write, not before)
4     investigate — for a bug: reproduce it BEFORE theorising
5     ── ask you ── should this be built, and shaped this way?
                    (and SPLIT it here, if it's several tasks)
6     ── ask you ── which architecture? only when the options are genuinely different
7–8   write the plan, break it into tasks
9     implement — small commits, one logical change each
10    pre-PR checks
11    VERIFY — drives the real app, evidence per row, cleans up after itself
12    DOCS — are the ADRs and PROJECT_MAP still true?   (11 chains into 12 automatically)
13    code review + security pass on Deep
14    ── ask you ── merge to PRE PROD?
15    review feedback loops back into 14
16    ── ask you ── promote to PRODUCTION?
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
| *"trim the comments"* / *"these docstrings are too long"* | `/dev:comment-budget` — existing code to the doc budget; reports unless `--apply` |
| *"draw the architecture"* / *"map this system"* | `/dev:arch` — a diagram whose every node is pinned to verified code; needs Archify |
| *"what's wrong with this app"* / *"the architecture is inconsistent"* | `/dev:survey` — finds bugs and drift, verifies each, files the confirmed |
| *"what should I work on?"* / nothing at all | `/dev:issues` — the tracker board, read-only. This is what bare `/dev` now does |

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

> **Budget: `shared/pipeline.md` stays at or under 995 lines** (995 at 2026-09-07). Not a style
> preference — attention per rule falls as the file grows, and a rule nobody reaches is worth less
> than no rule. At the ceiling, an addition is only allowed with a deletion in the same commit;
> `wc -l shared/pipeline.md` before you write. The number stays deliberately close to current: this
> file grew 593 → 938 on rules alone, and an unstated ceiling is not a ceiling. It has since lost
> rules — see the note below — which is the reason the gap is kept tight rather than comfortable.
>
> **2026-08-23 — raised 950 → 975, because the cheaper move was worse.** Staying under 950 for the
> Short Documentation rule was done by emptying Phase 9's Surgical Protocol into a pointer at the
> Guiding Principles table. Review found this optimised the line count while degrading exactly what
> the count is a proxy for: Phase 9 is the most-read phase in the file, and two relocated rules were
> strictly weaker at the destination — `Clean your own mess` lost *parameter*, `Commitment to flow`
> lost the actionable *delete it*. The bullets were restored and the ceiling moved instead.
> **Relocating a rule away from its point of use is not a deletion**, and does not pay for one.
>
> **2026-08-24 — corrected 975 → 958.** Raising by 25 to absorb 8 left 18 free lines, so the
> deletion-pays-for-addition gate would not have fired again for a long time, and the precedent set
> was *raise the ceiling* — available to every future addition. A ceiling with slack is not a
> ceiling. Take the smallest raise that admits the change, or take none. **960 was itself too
> loose** and was corrected to 958 in the same branch: at 957 the smallest admitting ceiling is
> 958, and 3 free lines would have let the next three additions land without paying anything.
> `ci/pr-gates.yml` now recomputes this rather than trusting the integer written here.
>
> **2026-09-06 — raised 958 → 988.** No deletion was available that would not degrade. The one the
> README has long named — Phase 11 delegating capture to `dev:shots` — does not pay: `dev:shots` owns
> the capture *commands*, Phase 11 only points at them in two lines. The 27-line teardown block is
> not a candidate either: `dev:launch-kill` does not cover the MCP-launched Chrome, so that rule
> lives nowhere else and Phase 11 is its point of use.
>
> **The breach ran silent for four PRs, which is the worse half.** The line above claimed
> `ci/pr-gates.yml` recomputes this; that file had never been installed. Its `line-budget` job now
> runs on its own at `.github/workflows/line-budget.yml`.

> **2026-09-07 — raised 988 → 995.** Phase 4 gained six lines telling it that a `dev:survey`-filed
> issue arrives with ladder layers 1–2 already done adversarially, and that layers 3–5 must run
> anyway because survey checks code and never runs the app. No deletion was available: Phase 13 is
> the standing candidate and is not one — under the "run /code-review" line it carries the
> spec-compliance check, the Deep-tier security triggers and the verdict handling, so cutting it is
> the 2026-08-23 failure exactly. Smallest raise, zero slack.

**5. Decisions are not steps.** Automation may skip asking between mechanical stages. It may never
skip a judgment — building, architecture, merging, promoting.

## Where to extend

| Change | Edit |
|---|---|
| Behaviour of any phase | `shared/pipeline.md` — **once**; all 7 entry points read it |
| A stack-specific addition | `shared/pipeline-{web,ios,android,kmp}.md` — these overlay Phases 10, 11, 14 only |
| A gate that belongs to an **event**, not a phase number | `shared/<topic>.md`, with its own *When this runs* table — `prod-secrets.md` binds to the merge that releases production, which is Phase 16 in a two-stage repo and Phase 14 in a single-branch one. Both phases point at it in two lines each. Bolting such a gate to one phase is how it misses the repo shape it was written for; that cost two review passes on 2026-08-12 |
| Platform know-how a phase needs **only sometimes** | `shared/<topic>.md`, a **lookup table read on demand** — `prod-secrets-apple.md` is read only when a missing secret matches a name in it. Not an overlay: it modifies no phase, so the phase stays stack-agnostic and costs nothing on repos that never hit it. Reach for this instead of an overlay when the content is *reference*, not *behaviour* |
| Branch/environment resolution | `shared/entry.md` |
| A new standalone member | `skills/<name>/SKILL.md` + a row in both family tables. **Only worth it for Phase 0 or a phase ≥ 11** — the rest pass reasoning, which cannot be handed over |
| A new **tool** (no phase) | Same, but it points at another tool rather than at `pipeline.md` — `launch-kill` reads `launch`'s Phase 2 for discovery. The no-copy rule is the same rule |
| A per-type issue template | the `dev:create-*` member itself — templates are the only thing those three doors hold |
| Entry routing | `SKILL.md` |

Members are ~60-line doors into the pipeline. **A member that copies pipeline content is a bug** —
they point, never duplicate.

## What not to change without a strong reason

- **The four always-stop gates.** They are the difference between a workflow and an autopilot.
- **The write boundary** (`shared/entry.md`). Name the target `owner/repo` before acting; never write
  outside the resolved repo without an explicit yes naming it; always cut a branch, from the
  resolved pre-prod branch and not from what is checked out. Paid for on
  2026-08-06 — a read-only version of this rule existed and did not stop two PRs being merged into
  another repo on a two-word instruction. **A boundary that only governs reads is not a boundary.**
- **The result-domain rule** (`shared/entry.md`). Say what an output *means* and what bounds it, not
  just where you looked. Paid for on 2026-08-06 → 08 — four confident wrong answers in one session,
  each a plausible **non-empty** result to a question narrower than the one asked. The empty-result
  rule (`dev:launch` 2.0 rule 2) existed the whole time and could not fire, because nothing was ever
  empty. **A rule that only governs absence does not govern reporting.**
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

## `docs/` is not in the clone — and switching branches deletes it

This repo git-ignores `docs/`, so ADRs (`docs/adr/`), diagrams (`docs/arch/`) and survey reports
(`docs/survey/`) live on one machine and are not on GitHub. That is a choice **here**; the skills
themselves write into `docs/` in whatever repo they run in, and check `git check-ignore -q docs/`
before doing so.

> **The trap, and it has already fired once.** `git rm --cached` untracks a file and leaves it on
> disk — but a later `git checkout` or `git pull` that moves you from a commit where `docs/` **was**
> tracked to one where it is not will **delete those files**. Being git-ignored does not protect
> them; that only applies to files Git was never tracking. On 2026-09-07 the untracking merge
> succeeded and the very next `checkout main && pull` removed 13 of 14 files, silently, in the
> command that reported success.
>
> **Recover them from the last commit that tracked them:**
>
> ```bash
> git restore --source=89102eb --worktree -- docs/
> ```
>
> `--worktree` restores the files without re-staging them, so they stay untracked. `89102eb` is the
> last commit on `main` where `docs/` was tracked. To find it again without that SHA, locate the
> commit that DELETED them and take its **parent** — the deleting commit itself no longer has the
> files:
>
> ```bash
> git restore --source="$(git log -1 --format=%H --diff-filter=D -- docs/adr)^" --worktree -- docs/
> ```

**Anything under `docs/` you want other people to have must be copied somewhere tracked.** The
journey GIF is the worked example: it lives at `assets/dev-journey.gif` precisely so the README still
renders on GitHub. A decision's losing options belong in the **PR body** for the same reason — see
`dev:docs`.

## Known gaps

Honest, as of 2026-08-04:

- **Epic support is new and unexercised (2026-08-04).** The design: file the parent with
  `/dev:create-epic`, split it at Phase 5 into real sub-issues, run `/dev #child` per slice — the
  pipeline stays task-shaped and the sub-issue list is the queue. Never run end to end.
- **No rollback — but two thirds of it is mechanical.** It runs 1 → 16 and stops, and nothing
  answers *"prod is broken, now what."* Spiked 2026-08-08, and the finding is that this is **not one
  gap**. Phase 16 applies schema BEFORE code, so a rollback has to run code-then-schema, and only
  the first half reverses:

  | Case | Reversible | How |
  |---|---|---|
  | **Code-only promotion** — no migration in the diff | **yes, always** | revert the promotion merge on the prod branch. Any platform that deploys on merge redeploys on revert — no platform rollback feature is involved |
  | **Additive migration** — new nullable column, new table, new index | **yes**, code only | old code ignores the new schema, so leave it forward. Must be *identified*, never assumed |
  | **Destructive migration** — drop, rename, narrowing type, overwriting backfill | **no** | the data is already gone. What exists is point-in-time **restore**, which also reverts every unrelated write since. That is not a rollback, and it is never autonomous |

  So a `dev:rollback` door's first job is **classification, not execution**: read the promotion
  diff, classify each migration, and refuse the third case while naming what a restore would cost.
  Phase 16 already computes the input it needs — `git log <prod>..<pre-prod>` — and already requires
  migrations applied before the merge, which is exactly what makes the three cases separable.

  **The trap it must not step in:** reverting the promotion merge on the prod branch does **not**
  revert pre prod, so the next promotion re-introduces the bad commit — and `git cherry` reports the
  branch clean, because patch-equivalence still sees the original. Observed 2026-08-06 in a
  two-stage repo: a revert landed on one branch while the other still held every reverted file. A
  rollback door must revert on **both** branches, or record the carry-forward where the next
  promotion will read it.
- **New-project path barely tested.** The `ARCHITECTURE.md`-absent branch and both MASTER_PROMPTs
  have never run.
- **The gate log has a mechanism but no data.** `## PIPELINE`'s `Gates:` line was added 2026-08-04
  to fix this; until ~20 PRs carry it, pruning is still guesswork. This buys visibility, not
  enforcement — see the self-reporting limit in the last bullet.
- **`dev:pre-prod`, `dev:review`, `dev:prod` — and where they CAN be exercised.** As of 2026-08-05
  `dev:pre-prod` has run end to end once, on a two-stage repo: branch → PR → gates → merge to the
  pre-prod branch. `dev:review` and the `pre-prod → prod` half of `dev:prod` still never have.
  **They cannot be proven in this repo, by construction, and running them here is not a gap to
  close — it is a category error.** This repo is single-stage: `entry.md` resolves pre prod and prod
  both to `main`, so Phase 16 correctly skips itself, and there is no feature branch to PR because
  commits land on `main` directly (which is also why `branch-guard.sh` is deliberately not installed
  here). Proving them needs a repo with a real `staging` → `prod` split **and** something worth
  promoting. Until that happens the honest status is *unexercised*, not *broken* — and an
  `/dev:prod` here reporting "single-stage, nothing to promote" is the skill working, not failing.
- **Enforcement is part mechanical as of 2026-08-05.** ~5 of 17 phases produce a durable artifact;
  the rest depend on the reader complying, and `## PIPELINE` / `## DOCS` are self-reported — a run
  that skips a phase *and* omits it from `Skipped:` is still invisible. Four hooks in `hooks/` now
  make Phases 1, 3, 12, 14 and 16 — plus Phase 11's teardown rule, though not its checklist —
  mechanical **where they touch a tool call**. That qualifier is the whole limit: a hook checks
  presence of state at a tool boundary, so Phases 4–8 are unreachable by construction, on the same
  seam that gives them no `dev-*` door. Pipe-tested only, **zero real runs**; `hooks/README.md`
  separates the three dated fixes from the undated design. `ci/pr-gates.yml`'s `required-sections` job stays
  **uninstalled** — `hooks/pr-gates.sh` supersedes it locally, and it would fail every PR here since
  these are not `/dev` runs. Its `line-budget` job **is** installed, at
  `.github/workflows/line-budget.yml` (2026-09-06): it reads three files and compares three numbers,
  so none of that reasoning applies to it. That is the repo's only mechanical PR check.
