# 0008 — Replace the board and surveyor rather than extend them

Status:  Accepted
Date:    2026-09-10
Commit:  (this branch)  ·  `feature/tracker-and-pipeline-state`

## Context

Two doors needed capabilities they were built to refuse.

`dev:issues` opened its `## Never` with *"Never cut a branch, never edit an issue, never start work.
**Read-only is the whole contract.**"* A board you cannot move a card on is not a board, so gaining
`move` / `cancel` / `delete` meant breaking that contract in as many words.

`dev:survey` hunted defects and architectural drift. A third hunt — performance, security and
quality opportunities — asks a different question of the same code and produces a different artifact
(`enhancement`, not a bug).

Both doors carry unusually dense scar tissue: `dev:issues` Phase 4.1's task-list parse exists
because a bare `#N` grep read an epic as `1/5` when the truth was `0/4`; 4.3 exists because two
branches with seven unmerged commits between them were invisible behind closed issues; `dev:survey`
Phase 5's two-checkers-each rule is what keeps a plausible-but-wrong finding out of the tracker.
Whatever happened next had to carry all of it.

## Decision

**Replace both.** `dev:kanban` supersedes `dev:issues`; `dev:ideation` supersedes `dev:survey`. The
old files are deleted, not deprecated.

Consequences accepted deliberately:

- **Every rule marked *verbatim* is copied unchanged, scars included** — dated incidents, counts and
  mechanisms move across intact, because the evidence is what makes the rule enforceable.
- **The read-only clause is replaced, not dropped.** `dev:kanban` Phase 7 defines three write tiers
  (move · cancel · delete-behind-a-gate) and `## Never` states outright that these *replace* the old
  contract — so a later edit making writes free is visibly a change the family did not agree to.
- **Retired names stay in the Entry 1 guard as aliases.** `/dev issues` and `/dev survey` map to
  their successors. Without this they fall through to "free text" and cut a branch named `issues`.
  This is the same rule `trim` earned on 2026-09-07.
- **`docs/` gains a fourth owned sibling:** `ideation/` (`dev:ideation`), joining `adr/`
  (`dev:docs`), `arch/` (`dev:arch`) and the now-historical `survey/`. Old reports are **not moved**
  — a report is dated evidence and relocating it breaks whatever cited it — so `dev:ideation` reads
  both directories.
- **Historical citations are not rewritten.** `docs/adr/0005` records `skills/survey/SKILL.md` at
  290 vs 161 lines at a named SHA; `docs/adr/0001` cites `skills/survey/SKILL.md:286`. Those stay,
  because rewriting dated evidence to match a rename falsifies the record.

## Rejected

**Extend the two existing doors in place.** Add writes to `dev:issues` and a third hunt to
`dev:survey`, keeping both names. Cheapest by far — no sweep of 18 cross-references, no guard
aliases, no ADR. Lost because `dev:issues`' name and its entire stated contract are *read-only*; a
door called "issues" that deletes issues is a name that actively misleads, and the contract sentence
would have had to be deleted anyway with nothing marking that it had been.

**Add new doors beside the old ones**, leaving `dev:issues` and `dev:survey` untouched. No
duplication risk in the files, and full backwards compatibility. Lost because it produces two pairs
of doors answering nearly the same question, and the family would carry 19 doors against
*Simplicity First* — with no way for a reader to know which of each pair is current.

**Keep the old names, change only the behaviour.** Rejected on the same ground as the first: a name
is part of the contract. `kanban` and `ideation` say what these now do.
