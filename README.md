# dev-skill

A personal development workflow for coding agents: take a GitHub issue or a plain description from
"what should this do?" all the way to production, without skipping the gates that matter.

`/dev` is the full run. **Fifteen members** sit around it: three `/dev:create-*` file the work item
before it starts, five are doors into the same pipeline at later phases for when the work already
exists and only that stage is needed, and seven are **tools** that map to no phase at all.

> **New here? Read [GUIDE.md](GUIDE.md).** Part 1 is what to type and what it will ask you;
> Part 2 is how to change it and what not to. This README is the repo's own structure.

---

## The order you actually use it in

The phase table below is the *reference*. This is the **journey** — what to type, in what order, and
what each door needs before it will do anything.

![The dev family, in the order you use it](assets/dev-journey.gif)

> The path lights up in the order you walk it: `survey` → file → pick → build → verify → docs →
> `/code-review` → pre prod → prod. Dashed edges are the ones that are never part of a straight run —
> the Phase 15 loop back into 14, and the tools.
>
> Drawn by `/dev:arch`, which pins every box to a file and line range at one commit and verifies it
> against a real Git object. `docs/` is git-ignored **in this repo**, so the explorable HTML is not
> in the clone — regenerate it with `/dev:arch the dev family`. Other repos track theirs normally;
> that is a choice here, not skill behaviour.

| # | You type | When | It needs | It gives you |
|---|---|---|---|---|
| 1 | `/dev:survey` | you don't know what's wrong yet | a repo | a report, then confirmed issues — each naming the run in `## Suspected`, which Phase 4 reads |
| 2 | `/dev:create-issue` · `/dev:create-bug` · `/dev:create-epic` | you already know | a description | an issue number |
| 3 | `/dev:issues` *(or bare `/dev`)* | the board is stocked | nothing | what's next, ranked |
| 4 | `/dev #N` | you picked one | an issue number | a branch, a plan, the code |
| 5 | `/dev:verify` | the code exists | a branch | evidence per row → **chains to 6** |
| 6 | `/dev:docs` | before any merge | a diff | the PR's `## DOCS` section |
| 7 | `/code-review` | before any merge | a diff | findings — **not a `dev:` door** |
| 8 | `/dev:pre-prod` | gates are green | a branch | a PR, merged to pre prod |
| 9 | `/dev:prod` | pre prod is verified | both branches | production |

**Steps 1–3 happen before any branch exists.** They take a description and produce an issue number —
nothing durable is being worked on yet, which is why they can run in any session.

**Step 4 is the only one that plans.** Phases 1–10 pass *reasoning* between each other, and reasoning
lives only in the conversation that produced it. That is why there is no door into Phase 6 — there
would be nothing to hand it.

**Steps 5–9 each take a durable artifact** — a branch, a diff, a PR number — which is exactly what
makes them independently invocable. Enter at 5 on Monday and at 8 on Friday; neither needs the other
still in context.

### What moves between the doors

```
description ─▶ issue #N ─▶ branch ─▶ diff ─▶ PR # ─▶ pre prod ─▶ production
```

Each step is a **durable handoff** — nothing needs the previous door's conversation to still exist,
which is why the family is doors rather than one long run. `dev:survey` enters at the front;
`dev:review` is the one arrow that goes backwards, looping a PR into Phase 14.

`verify` (11) → `docs` (12) is the **only** pair that chains without asking — same diff, both
read-only, two halves of one PR body. Nothing ever chains into a merge or a promotion. The seven
tools map to no phase and can be called any time.

---

## Layout

```
shared/           ALL the behaviour — pipeline.md is Phases 0-16, entry.md is repo and
                  branch resolution, plus platform overlays and the prod-secrets tables
skills/           one directory per door; each points into shared/, none copies it
SKILL.md          the full run — entry routing + family table
install.sh        links this repo into every agent CLI on the machine
assets/           the map above, tracked so the README renders
docs/             GIT-IGNORED — ADRs, diagrams and survey reports stay local
hooks/  ci/  .github/workflows/    4 Claude Code hooks; line-budget.yml is the only
                  mechanical PR check. web/ and mobile/ hold conditional prompts
```

**Behaviour changes go in `shared/`, once.** That is the whole structure: one pipeline, many doors.

### Tools, not phases

`dev:launch` · [`dev:launch-kill`](skills/launch-kill/SKILL.md) · `dev:shots` map to no phase and
read none of the pipeline — three verbs on one noun, and the latter two are doors into `launch`
rather than copies of it. [`dev:arch`](skills/arch/SKILL.md) is the only third-party dependency
([Archify](https://github.com/tt-a1i/archify)) and stops rather than drawing something unvalidated.

Phase 11 should delegate capture to `dev:shots`; that edit waits on a deletion to pay for it, since
`shared/pipeline.md` sits at 995 against a 995-line budget.

---

## Running it on another CLI

The workflow is portable; only the packaging is Claude Code's. `./install.sh` links it into every
agent CLI on the machine that uses the `skills/<name>/SKILL.md` convention:

```
$ ./install.sh
  claude       already linked, unchanged
  codex        linked  ~/.codex/skills/dev
  antigravity  not found — skipped
```

What transfers and what needs substituting:
[GUIDE.md → Running it on another CLI](GUIDE.md#running-it-on-another-cli).

---

## Installing under Claude Code

A **skills-dir plugin** — it lives directly in `~/.claude/skills/`, no marketplace, no plugin cache.
One symlink installs the whole family.

```bash
ln -sfn ~/Developer/skills/dev-skill  ~/.claude/skills/dev
```

Auto-loads next session as `dev@skills-dir`; `/reload-plugins` loads it now.

**The namespace comes from `.claude-plugin/plugin.json`, not from directory names** — which is why
the members are `verify` and `launch`, not `dev-verify` and `dev-launch`. Without that manifest the
same tree registers **nothing**: plain skill discovery is flat and never looks inside `skills/`.

**Verify against the loaded skill list, not the filesystem.** A `SKILL.md` on disk proves nothing
about registration — check `claude plugin list`.

---

## The pipeline

| Phase | | Sibling |
|---|---|---|
| **0** | **Filing** — draft, resolve real labels, create. Standalone only; a `/dev` run never reaches it. `dev:survey` files through these | `dev:create-*` |
| 1 | Context Load — `PROJECT_MAP.md`, `ARCHITECTURE.md`, existing spec | |
| 2 | Tech Stack & Discovery — stack detect, conditional explorer fan-out | |
| 3 | Git Branch Naming | |
| 4 | Investigation — evidence ladder, reproduce before theorising; a `dev:survey` issue starts at layer 3, never skips 3–5 | |
| **5** | **Discuss Before Building** — plain-language, explicit go-ahead; **asks for YOUR approach before showing its own**; conditional UI discussion **and epic decomposition** | |
| 6 | Architecture Alternatives — 3 forced-different biases, losers recorded | |
| 7 | Plan Output — written to `specs/` | |
| 8 | Task Breakdown | |
| 9 | Implement — surgical protocol | |
| 10 | Pre-PR Quality Checks | |
| **11** | **Verification Gate** — agent-run, evidence per row, teardown → chains to 12 | `dev:verify` |
| **12** | **Docs & Decisions Gate** — ADRs before merge | `dev:docs` |
| 13 | Code Review Gate — `/code-review`, + `security-review` on Deep | |
| **14** | **PR → Review → Merge → Pre Prod** | `dev:pre-prod` |
| **15** | **Review Cycle** — a LOOP back into Phase 14, never forward | `dev:review` |
| **16** | **Prod Promotion** — secrets pre-flight, then migrations, never autonomous | `dev:prod` |
| — | *(no phase)* — build & launch the app | `dev:launch` |
| — | *(no phase)* — stop this project's servers | `dev:launch-kill` |
| — | *(no phase)* — capture screens from the running app | `dev:shots` |
| — | *(no phase)* — bring EXISTING code to the documentation budget | `dev:comment-budget` |
| — | *(no phase)* — draw a verifiable diagram of a system | `dev:arch` |
| — | *(no phase)* — survey an existing app, file the confirmed findings. **Feeds Phase 0** via `dev:create-*`, and Phase 4 reads the provenance it writes | `dev:survey` |
| — | *(no phase)* — the tracker: current, next, stats | `dev:issues` |

### Why these phase members and not others

Phases 1–8 pass **reasoning**, which lives only in the conversation that produced it. From Phase 11
on, every phase takes something durable — a branch, a diff, a PR number — which is what makes it
independently invocable. Phase 0 qualifies from the other side: it runs *before* any reasoning
exists. Phase 13 is deliberately absent — it is twenty lines that mostly say "run `/code-review`".

Fuller version, with the four other design ideas:
[GUIDE.md → The five ideas the design turns on](GUIDE.md#the-five-ideas-the-design-turns-on).

---

## Design rules

- **Right-size first** — Light / Standard / Deep, stated before starting. Light is the default.
- **It runs straight through.** Only Phases 5, 6, 14 and 16 stop; those are decisions, not steps.
- **Never end silently.** Every stop names the next phase and asks.
- **Skipping leaves a trace** — `## PIPELINE` in the PR says what was skipped and *why*.
- **Pre prod ≠ prod.** Phase 14 reaches pre prod; promotion is Phase 16 and never autonomous.
- **Evidence before assertions.** Run it, read the output, paste what it printed.
- **Docs before merge.** A number or decision changed without its ADR is an unfinished diff.
- **One pipeline, many doors.** Members point into `shared/pipeline.md`; they never copy it.
- **The repo is a write boundary**, and **a result is not a claim** — both defined once in
  [`shared/entry.md`](shared/entry.md), which every door reads.

Why each exists, with the incident behind it:
[GUIDE.md → The five ideas the design turns on](GUIDE.md#the-five-ideas-the-design-turns-on).

---

## Editing

Edit here — `~/.claude/skills/dev` symlinks to this repo. After changing anything under
`shared/`, every phase skill picks it up with no further action.
