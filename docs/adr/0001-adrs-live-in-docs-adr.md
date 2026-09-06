# 0001 — ADRs live in `docs/adr/`, numbered, superseded rather than edited

Status:  Accepted
Date:    2026-09-06
Commit:  (this PR)

## Context

`dev:docs` has required an ADR for "a decision with a rejected alternative" since it was written, and
`skills/survey/SKILL.md:286` delegates to it explicitly — *"`dev:docs` owns ADRs, their numbering and
location are its rules, not this skill's."* Neither rule existed. `dev:docs` named no directory, no
numbering, and no shape.

So every decision this repo has made lives in commit messages and PR bodies. Two of them
(`0002`, `0003`) were squash-merged, and their commits no longer exist on `main` at all — the
reasoning survives only on GitHub, which is not in the clone. One (`0006`) was never written down
anywhere.

## Decision

`docs/adr/NNNN-kebab-title.md`, four digits, monotonic. `docs/adr/README.md` is the index, one line
per ADR. The number is **allocated by reading the directory**, never guessed.

A landed ADR's `## Decision` is never edited. It is superseded by a new ADR, and the old one's
`Status:` is updated to point at it.

An ADR with an empty `## Rejected` is a note, not an ADR — if nothing lost, there was no decision,
and it belongs in the skill file instead.

## Rejected

- **A flat `DECISIONS.md`** — append-only files stop being read at about twenty entries, and there is
  no way to supersede one entry without editing the record of what was previously believed.
- **No convention; keep relying on commit messages** — this is what the repo was already doing, and
  squash merges delete it. That is the defect, not the status quo.
- **Guessing the next number from the highest one you remember** — the same defect class as the three
  wrong line counts that forced the CI budget check in the first place (`GUIDE.md`, 2026-08-23/24).
- **A new failing gate in `dev:docs` when a decision has no ADR** — the requirement already exists;
  a second gate that must *infer* whether a diff carries a decision would fire on correct work, and
  `ci/pr-gates.yml` already records that as how a check gets ignored.

## Consequences

Seven ADRs are backfilled with this one, so the convention starts populated rather than aspirational.
`docs/` now has three siblings with three owners: `adr/` (`dev:docs`), `survey/` (`dev:survey`),
`arch/` (`dev:arch`).

The cost is a file per decision, and the discipline of writing the losing options down while they are
still fresh. Writing them later means writing them from memory, and memory keeps the conclusion while
losing the reason.

## Evidence

```
$ grep -n "docs/adr\|where.*ADR\|numbering" skills/docs/SKILL.md
(no output)

$ git merge-base --is-ancestor 9a765c4 origin/main; echo $?
1                       # 0002's reasoning: not on main
```
