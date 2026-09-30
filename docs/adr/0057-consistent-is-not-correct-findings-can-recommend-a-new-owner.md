# 0057 — Consistent is not correct: findings can recommend a new owner when defects trace to the old one

Status:  Accepted
Date:    2026-09-30
Commit:  (this commit)

Amends `skills/findings/SKILL.md` → Phase 6 rules 2 and 5 and the matching `## Never` line, and adds the
checks that make the amendment evidence-bound (Phase 2's decision records, Phase 4's ownership inventory).
`dev:ideation` inherits both through the protocol it shares with `dev:findings`.

## Context

Phase 6 said *recommend the pattern the codebase already mostly is* and *never recommend a pattern
absent from the codebase*, with *"a rewrite wearing the word unify"* as the reason. The rule exists
because unprompted rewrite advice never ships.

On 2026-09-30 the developer reviewed a take-home iOS app whose own audit had quoted that phrase
verbatim in an ADR, rejecting view models because the code "is already consistent on one pattern". A
code review of the same app then returned four findings — a distorted and a stale photo, a favourite
rollback race, a screen holding a stale copy of its contact — that shared one cause: state owned in the
wrong place, consistently. Working through `ContactDetailView` line by line, the developer designed the
fix themselves: a view model per contact holding presentation and actions, a cache actor as the only
owner of images, display-only views, and a store that owns only the list — a pattern the codebase did
not use at all, and which the rule forbade recommending.

The rule had turned "consistent" into "fine". A pattern applied everywhere can misplace state
everywhere, and no consistency sweep sees it, because there is no split to see.

The developer, 2026-09-30: *"this is the approach that i belong to it not the one u suggested"* ·
*"keep in mind not this project only"*.

## Decision

- **The majority pattern stays the default recommendation — unless confirmed findings trace to it.**
  Then the recommendation is the ownership that removes them, written as individual moves, each naming
  the confirmed findings it removes. A move no confirmed finding traces to is not recommended; the
  anti-rewrite intent is kept, and made checkable.
- **"It is already consistent" is a clean result only once the ownership inventory is clean too.**
- **Each finder builds a state-ownership inventory per UI unit** (Phase 4), in stack-neutral terms: stale
  copies, look-up-able data, one selection in two places, views that load, data-source decisions in
  views, display-only components that know their source, one component's state in a shared store, and
  models holding dependencies they only use to answer events.
- **Decision records are evidence** (Phase 2): unkept promises, rejections whose reason no longer
  holds, records or tests pinning known-wrong behaviour, and the absence of any ownership decision.
- `dev:code-review` asks the same ownership questions of state a diff adds (Phase 4b) and gains a
  records-and-claims pass (Phase 4c).

## Rejected

```
rejected: drop the majority rule entirely — reopens unprompted rewrite advice, the failure it was written for
rejected: allow a new pattern when "the developer would like it" — a preference is not evidence; the
          trigger has to be confirmed findings, or the report cannot be argued with
rejected: add ownership as another consistency split in 4b — a misplacement applied everywhere has no
          minority site to anchor at; it needs its own inventory
rejected: write the lens for SwiftUI, where it was observed — the family runs on web, Android and
          backend repos too; the rule is stated in stack-neutral terms with examples from each
```
