---
name: roadmap
description: >
  Proposes what to build NEXT, from evidence the repo already wrote down — its recorded gaps,
  PROJECT_MAP's ORPHANS & PENDING, and prior `dev:survey` / `dev:ideation` reports — then writes the
  accepted themes as GitHub MILESTONES with EPIC PARENTS underneath. The milestone is what
  `dev:kanban` reads as its QUEUE column, so this is the door that makes a queue exist.
  Files PARENTS ONLY: slices are cut at Phase 5 on the first `/dev #E`, where investigation has
  actually happened. Declined themes are recorded as closed `not planned`, so a rejected direction
  is never re-proposed.
  It NEVER invents work. A roadmap is the easiest artifact in this family to hallucinate, and one
  built from imagination is worse than none because it looks like a plan.
  Trigger on: "what should we build next", "roadmap", "plan the next quarter", "what are the
  themes", "group the backlog", "what's the plan", "set up milestones", "what's our direction".
allowed-tools: [gh, git, rg, grep, Read]
---

# roadmap — what to build next, from what the repo already knows

A **tool**, not a phase. It sits **upstream of Phase 0** beside `dev:survey` and `dev:ideation`, and
downstream of both: they find things, this one decides what the findings add up to.

**It proposes and writes containers. It never decomposes and never starts work.**

| This door writes | This door never writes |
|---|---|
| GitHub **milestones** — one per accepted theme | slices or child issues (Phase 5 owns those) |
| **Epic parents** via `dev:create-epic` | code, branches, or a PR |

## The loop it closes

```
dev:survey ─┐
dev:ideation ┴▶ docs/{survey,ideation}/<date>.md ─┐
PROJECT_MAP.md → ORPHANS & PENDING ───────────────┤
the repo's own recorded gaps ─────────────────────┤
                                                  ▼
                                            dev:roadmap
                                                  │
                              milestone M ─┬─ epic E1  (parent only)
                                           └─ epic E2
                                                  │
                            dev:kanban QUEUE ◀────┘  (M is the queue)
                                                  │
                      /dev #E1 → Phase 5 cuts slices → children
                                                  │
                       dev:kanban 7.3 closes E1, then closes M
```

`dev:kanban` **7.3 owns the closing**, not this door. This one opens containers; that one notices
when they are done.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | read the evidence, propose themes | this |
| `show` | render the current roadmap only — read-only, propose nothing | propose |
| A theme name | that theme only — refine or extend it | all |

## Phase 2 — Resolve the repo, then read what ALREADY exists

Read `~/.claude/skills/dev/shared/entry.md` — **the absolute path, because this skill runs inside
somebody else's repo.** The resolved repo is the boundary for reading, writing and filing.

**Read the current state before proposing anything.** A roadmap that duplicates what is already
planned is worse than no roadmap:

```bash
gh api repos/<owner>/<repo>/milestones --jq '.[] | "\(.title) | \(.open_issues) open / \(.closed_issues) closed | due \(.due_on)"'
gh issue list --state open  --label epic --json number,title,milestone
gh issue list --state open  --limit 200 --json number,title,labels,milestone
gh issue list --state closed --search 'label:roadmap-declined' --json number,title,body
```

Four things come out of this, and all four constrain Phase 4:

1. **Open milestones** — themes already accepted. Extend, never re-propose.
2. **Epic parents** — work already scoped.
3. **Unmilestoned open issues** — the backlog a theme might gather up.
4. **`roadmap-declined`** — themes you already said no to. **A decision is not a gap.**

**If `gh` errors or Issues are disabled, say so and stop.** An empty tracker and a failed query must
never render the same — `dev:kanban` Phase 3's rule.

### The active milestone

`dev:kanban`'s QUEUE column is *the active milestone's members*, so exactly one milestone is active
at a time. **Active = the open milestone with the nearest `due_on`**; if none has a due date, the
oldest open one. Say which one you resolved and why. If two are equally near, **ask** — a queue that
silently picks one is a queue nobody can trust.

## Phase 3 — Discover from evidence, never from imagination

**This is the phase where a roadmap goes wrong.** Every theme must trace to something already
written down in this repo. Read all four sources, and say which produced what:

| Source | Find it with |
|---|---|
| The repo's self-declared gaps | `grep -rnE "^## (Known gaps\|Known limits)" --include="*.md"` |
| The family's honesty convention | `grep -rn "Undated, therefore unproven" --include="*.md"` |
| Deferred work in a spec's status line | `grep -rniE "^\*\*Status.*(deferred\|NOT (implemented\|executed))"` |
| `PROJECT_MAP.md` | its `ORPHANS & PENDING` section |
| Prior findings | `docs/survey/*.md` and `docs/ideation/*.md` — **read both**, the directories split on 2026-09-10 |
| The tracker | unmilestoned open issues from Phase 2 |

**Print each candidate with its source, before proposing anything.** A theme you cannot point at a
line for is one you invented, and everything built on it inherits that.

**If the repo records nothing, say so and stop proposing.** *"This repo declares no gaps, has no
`ORPHANS & PENDING`, no prior reports and an empty tracker — I have no evidence to build a roadmap
from"* is a complete and honest answer. Offer `dev:survey` or `dev:ideation` to **generate** the
evidence, then come back. **Manufacturing a roadmap to fill the silence is the failure this phase
exists to prevent** — and unlike an invented backlog item, an invented *theme* shapes months of
work before anyone notices it rested on nothing.

**Out of scope, deliberately: competitor and market analysis.** It produces claims nothing in this
repo can verify, which is the opposite of how every other door here works. If you want it, it is a
conversation, not a phase.

## Phase 4 — Propose themes

A **theme** groups evidence that shares a *reason*, not a directory. "Everything in `auth/`" is a
folder; "the app cannot be trusted with credentials until these four land" is a theme.

For each proposed theme:

```
<theme name>
  because:   <the shared reason>
  evidence:  <file:line or #N>, <…>          ← every item traceable to Phase 3
  epics:     <1–4 parent-sized pieces>
  not now:   <what is deliberately outside it>
  cost of doing nothing: <…>
```

**Rank them, and mark the ranking as YOURS.** Say why in a clause — *"first because it is the only
one here that loses data"* — so it reads as a claim that can be argued with rather than a priority
handed down. This is `dev:kanban` 6b's rule applied at theme scale.

**Three to five themes, not twelve.** A roadmap nobody can hold in their head is a backlog with
headings.

**`not now:` earns its place.** It is the same section as `dev:create-epic`'s `## Out of scope`, at
one level up, and for the same reason: a theme without a stated boundary grows one epic at a time
and nobody can point at when it happened.

## Phase 5 — Confirm, one theme at a time

**Nothing reaches GitHub without a yes.** This is a gate, not a formality: milestones and epics are
the containers everything downstream is filed into, and a wrong one is expensive precisely because
it looks organised.

Per theme, in order: state it, ask, wait. **Never batch** — a list of five themes gets one answer
about the last one.

Three outcomes:

| Answer | What happens |
|---|---|
| **accept** | Phase 6 writes the milestone and its epic parents |
| **defer** | nothing is written; it stays in the report for a later run |
| **decline** | Phase 6 records it as declined, so it is never re-proposed |

**A declined theme is written down, not forgotten.** File it, close it as `not planned` with the
reason as a comment, and label it `roadmap-declined`. Phase 2 reads those back. Without this, every
run re-proposes what you already rejected, and the door becomes noise.

## Phase 6 — Write: milestones and PARENTS ONLY

**Name `owner/repo` out loud before the first write** (`shared/entry.md` rule 2).

```bash
gh api repos/<owner>/<repo>/milestones -f title="<theme>" -f description="<the because + not now>" [-f due_on=...]
```

Then, per epic in the theme, hand to **`dev:create-epic`** — do not hand-roll the body. That door
owns the template (`## Goal`, `## Why now`, `## In scope`, `## Out of scope`, `## Done when`) and
its guards. Assign each epic to the milestone as it is created.

**PARENTS ONLY. No slices, not even as `- [ ]` lines.** `dev:create-epic` states why: cut here they
would be *imagined from a description*, and a wrong slice boundary is expensive because each slice
becomes a branch, a PR and a promotion. Phase 5 of the pipeline cuts them on the first `/dev #E`,
after context load, stack discovery and investigation have run.

**`## Done when` is the epic's completion condition, and `dev:kanban` 7.3 is what evaluates it.**
Write it so it can be: observable, epic-level, true only when every child is closed.

**Labels are read, never assumed** — `gh label list`. If the repo has no `epic` label, offer to
create it; `dev:kanban` 4.1 keys on it, and without it an epic parent will be offered as startable
work. Same for `roadmap-declined`.

**After writing, offer `dev ui roadmap`** — it regenerates `.dev/ui/roadmap.html` from the milestones
and epics that now exist. Generated output; regenerate rather than trust.

## Phase 7 — Render, then hand off

```
## <repo> — roadmap

ACTIVE    <milestone>            3 epics · 0/9 slices · due <date>      ← dev:kanban QUEUE
NEXT      <milestone>            2 epics · not started
LATER     <milestone>            1 epic

DECLINED  <theme> — <reason>, <date>

evidence: <n> items from <k> sources        proposed <n> · accepted <n> · declined <n>

→ start #E1, or open the board?
```

**End by asking, never by listing** — `dev:kanban` Phase 6's rule. Naming an epic hands to
`/dev #E`, which decomposes it at Phase 5. This door does not start work.

## Never

- **Never invent a theme.** Every one traces to Phase 3 evidence, printed with its source.
- **Never file slices or child issues** — `dev:create-epic`'s rule, and Phase 5 of the pipeline owns
  decomposition.
- **Never write without an explicit yes per theme** (Phase 5). Batching is not consent.
- **Never re-propose a `roadmap-declined` theme.** A decision is not a gap.
- **Never close a milestone or an epic** — `dev:kanban` 7.3 owns that, because it is the door that
  computes `n/n`.
- **Never make two milestones active.** QUEUE is one column; ambiguity there breaks the board.
- **Never do competitor or market analysis.** Nothing in the repo can verify it.
- **Never manufacture a roadmap to fill an empty repo** (Phase 3). Offer to generate evidence
  instead.
- **Never write to a repo other than the resolved one.**
- **Never start work.** Naming an epic hands to `/dev #E`.

## Known limits

| | |
|---|---|
| Themes come from what the repo wrote down | A repo that records nothing gets an honest refusal, not a guess |
| No competitor or market input | Deliberate — unverifiable from here |
| One active milestone | If the repo runs parallel releases, QUEUE shows one of them and says so |
| Milestone due dates are optional | With none set, "active" falls back to the oldest open milestone, which may not be what you meant — it says which it picked |
| It cannot tell a stale theme from a slow one | An old milestone with no closed issues may be abandoned or merely patient. It reports the dates and asks |

## Scar tissue

**2026-09-10 — written to close a loop that had no terminator.** Before this door, nothing in the
family created a milestone: the only mention of the word in the real files was a `gh issue view
--json …,milestone` in `SKILL.md` that fetched the field and never used it. `dev:kanban`'s QUEUE
column existed but had never rendered, because nothing made a queue.

**The reference framework this was modelled on generated roadmaps with competitor analysis** — 17
features, MoSCoW priorities, 24 competitor insights. That half was deliberately not adopted: its
claims cannot be checked against the repo, and every other door in this family refuses to file what
it cannot verify. A roadmap is the artifact where that discipline matters most, because it is the
one people plan from.

**Undated, therefore unproven:** this door has never been run. The active-milestone resolution, the
`roadmap-declined` round trip, and whether three-to-five themes is the right ceiling are all
designed rather than observed.
