# 0020 — Impact and complexity are labels the doors propose

Status:  Accepted
Date:    2026-09-12
Commit:  (this branch)  ·  `feat/macos-app-missing-features`

## Context

A board can be ranked here by one thing: the priority label, `P1`–`P3`. Priority answers *when*,
and it is read that way — `dev:kanban` Phase 5 orders NEXT by it. Nothing records what an issue is
**worth** or how **big** it is, so those two live only in whoever filed it.

`dev:ideation` already computes both. Its Phase 6 ranks every opportunity by gain over cost, and its
Phase 9 files the issue with a priority label derived from that ratio — the two numbers that
produced the ranking are thrown away at the moment of filing, and the next reader cannot tell a
cheap win from an expensive one.

The developer asked for both on the board's cards (2026-09-12), and chose that the doors should
propose the values rather than the app alone.

## Decision

Two label families, `impact:high|medium|low` and `complexity:high|medium|low`, created in this
repository on 2026-09-12.

- **Impact is the gain; complexity is the cost.** Priority is unchanged and still means urgency, so
  `dev:kanban`'s ordering is untouched.
- **Every filing door proposes both, marked as an assumption**, for the developer to correct:
  `create-issue`, `create-bug`, `create-epic`, `survey`, `ideation` and `roadmap`. `dev:ideation`
  carries its own two numbers across rather than inventing new ones.
- **A repository lacking a label is offered it, never given it silently** — the rule `dev:roadmap`
  already applies to `epic` and `dev:kanban` to `P1`–`P3`, which also refuses to bulk-relabel a
  tracker because applying a rating to 200 issues invents 200 ratings.
- **Dev Desk shows a dash for an unrated issue**, so a rated card and an unrated one are never
  confused. The vocabulary is documented in `docs/guide/WORKFLOW.md` → *Rating an issue*.

## Rejected

- **Only the doors with evidence rate** (ideation from its numbers, survey from severity), leaving
  the `create-*` doors to ask. Lost because every hand-filed issue would then arrive unrated, which
  is most of them, and the board would be mostly dashes.
- **The developer rates everything in the app**, with no door writing a rating. Honest, and every
  value would be a human's. Lost because the doors hold the evidence at the moment of filing —
  ideation literally computed the gain — and asking the developer to re-derive it later wastes it.
- **Map impact onto `P0`–`P3`.** No new labels, and the taxonomy stays small. Lost because priority
  is urgency: a high-impact improvement nobody needs this quarter is `P3` with `impact:high`, and
  collapsing them loses exactly that distinction. Complexity would still have no source.
- **An "unrated" chip instead of a dash**, clickable to rate. Lost because it turns every unlabelled
  card into a prompt the board did not ask for.
- **Record them in `.dev/` state rather than labels.** Lost because a label is readable by `gh`,
  by every other door and by anyone on github.com, while `.dev/` is local to one checkout.

## Consequences

- **Six doors change**, and each now asks at most what it could not infer — the ratings are drafted
  with the issue, not interviewed.
- **Each repository needs the labels created once.** Until then a door offers, and the board shows
  dashes; nothing fails.
- **`shared/pipeline.md` is untouched.** It sits at the 995-line ceiling `docs/guide/CONTRIBUTING.md`
  states, where an addition demands a deletion in the same commit, so the vocabulary lives in the
  guide and each door references it.
- **A rating is a proposal until the developer confirms it.** A door that files one unconfirmed has
  invented a number, which is the failure `dev:kanban`'s never-bulk-relabel rule exists to prevent.

## Evidence

```
gh label list -R hasansa007/dev-skill --limit 100 --json name -q '.[].name'
→ … epic impact:high impact:medium impact:low complexity:high complexity:medium complexity:low

swift test --package-path apps/desk/DeskCore
→ 256 tests, 0 failures
```

The nine issues filed for this epic (#59–#67) carry both labels, proposed by the run that filed them
and corrected by the developer before creation.
