# 0008 — Replace the board; ADD the opportunity door rather than merge it into the surveyor

Status:  Accepted
Date:    2026-09-10
Commit:  (this branch)  ·  `feature/tracker-and-pipeline-state`

## Context

Two doors needed capabilities they were not built for, and the right answer differed for each.

`dev:issues` opened its `## Never` with *"Never cut a branch, never edit an issue, never start work.
**Read-only is the whole contract.**"* A board you cannot move a card on is not a board, so gaining
`move` / `cancel` / `delete` meant breaking that contract in as many words — and the door's own name
asserts the contract it would be breaking.

`dev:survey` hunted defects and architectural drift. A third question — *what does this do
adequately that could be materially better?* — asks something else of the same code and produces a
different artifact (`enhancement`, not a bug).

Both doors carry unusually dense scar tissue. `dev:issues` Phase 4.1's task-list parse exists
because a bare `#N` grep read an epic as `1/5` when the truth was `0/4`; 4.3 exists because two
branches carrying seven unmerged commits between them were invisible behind closed issues;
`dev:survey` Phase 5's two-checkers-each rule is what keeps a plausible-but-wrong finding out of a
tracker. Whatever happened had to carry all of it.

## Decision

**Different answers for the two doors, because the problems were different.**

**`dev:board` REPLACES `dev:issues`.** The name asserted the contract that was changing, so both
had to go together. Every rule marked *verbatim* is copied unchanged, scars included. The read-only
clause is **replaced, not dropped**: Phase 7 defines three write tiers (move · cancel ·
delete-behind-a-gate) and `## Never` states outright that these supersede the old contract — so a
later edit making writes free is visibly a change the family did not agree to.

**`dev:ideation` is ADDED beside `dev:survey`, which stays.** Merging the opportunities hunt into
the surveyor and renaming the result `dev:ideation` was tried first and reverted the same day: two
of the merged door's three hunts were defect-finding, and finding a null-deref is not ideation. A
name that misdescribes two-thirds of what a door does will mislead someone into skipping it.
`dev:survey` was restored **byte-identical from history** rather than rewritten, so its scars are
the originals.

Consequences accepted deliberately:

- **The family grows by one, to 18 doors at the time of this decision**, against *Simplicity First*. Paid for accuracy of naming. (It reached 21 later on the same branch — see `dev:roadmap`, `dev:insights` and `dev:code-review`.)
- **Two doors discover the same flows and fan out the same way**, so running both doubles the
  family's largest spend. Both intros say run one, and say defects first — what is broken changes
  which improvements are worth making.
- **`dev:survey` is the single source of truth for the shared protocol** (Phases 2, 3, 4, 5, 8).
  `dev:ideation` cross-references it rather than copying ~200 lines that would drift, the same way
  `dev:survey` already delegates ADRs to `dev:docs`.
- **Retired names stay in the Entry 1 guard as aliases.** `/dev issues` maps to `dev:board`.
  Without it, it falls through to "free text" and cuts a branch named `issues` — the rule `trim`
  earned on 2026-09-07. `survey` needs no alias: it is a live door again.
- **`docs/` gains a fourth owned sibling:** `ideation/` (`dev:ideation`), joining `adr/`
  (`dev:docs`), `arch/` (`dev:arch`) and `survey/` (`dev:survey`).
- **Historical citations are not rewritten.** `docs/adr/0005` records `skills/survey/SKILL.md` at
  290 vs 161 lines at a named SHA. Rewriting dated evidence to match a rename falsifies the record.

## Rejected

**Extend the two existing doors in place** — add writes to `dev:issues`, a third hunt to
`dev:survey`, keep both names. Cheapest by far. Lost for the board because `dev:issues`' name and
entire stated contract are *read-only*, and a door called "issues" that deletes issues actively
misleads; the contract sentence would have been deleted anyway with nothing marking that it had
been.

**One door with three hunts, named `dev:ideation`** — built, merged, and reverted within hours. Lost
because the name described one hunt of three. Kept as scar tissue in `skills/ideation/SKILL.md`
rather than erased, since the failure is instructive: a rename that improves one axis can silently
misdescribe two others.

**New doors beside the old ones for BOTH** — leave `dev:issues` untouched too. Full backwards
compatibility, no sweep. Lost because it produces two boards answering the same question with no way
for a reader to know which is current. The surveyor case is different precisely because the two
doors answer **different** questions.

**Keep the old names, change only the behaviour.** A name is part of the contract. `board` says
what the board now does; `ideation` says what the new door asks.
