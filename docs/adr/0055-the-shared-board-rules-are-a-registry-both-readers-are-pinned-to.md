# 0055 — The shared board rules are a registry both readers are pinned to

Status:  Accepted
Date:    2026-09-21
Commit:  (this commit)

Amends [0013](0013-the-app-reads-git-and-github-directly.md), whose consequences
section accepted that a divergence between `scripts/dev.py` and `BoardBuilder.swift` "is caught only if both
test suites are remembered". It does not reverse 0013 — the app still reads git and GitHub directly, and the
two implementations stay two implementations. What it removes is the honour system in front of them.

## Context

The duplication 0013 accepted has drifted twice.

An issue with an open pull request read Review in Dev Desk and In progress in `dev board` for as long as both
columns existed, because nothing ever put a `pr` into an issue's facts; it was repaired by hand on 2026-09-20.
Days later, ADR 0054 moved Claude Code's install root, `scripts/dev.py` followed, and Dev Desk did not — six
Swift literals went on naming a path a plugin install never creates, and roughly twenty tests pinned that path
as correct, so the suite was green while every agent launch was broken (#88). The `/dev` run that found it had
itself been started with the dead path.

Both escapes share a shape. Neither was a shared rule changing its value: each was **one reader gaining or
moving something the other never had**. A fixture that only compares outputs would have caught neither.

Measured before deciding: both readers were run over 42 inputs covering every edge their regexes were written
for — `gh-120-thing` against issue 12, `unfix #9`, `fixes#6`, `sliced 3`, an indented checklist, a bare `#N` in
prose. **Zero divergences.** The rules agree today; what is missing is anything that keeps them agreeing.

## Decision

`shared/board-rules.json` holds the shared rules as **cases, not code** — seven rules, 49 cases — and is a
**registry** as well as a fixture. Both suites bind every rule named in it and **fail on a rule they do not
bind**: `tests/state/test_board_conformance.py` against `scripts/dev.py`,
`apps/desk/DeskCore/Tests/DeskCoreTests/BoardConformanceTests.swift` against `BoardBuilder`.

Adding a rule to the registry breaks both builds until both readers implement it, which is the failure mode
that actually occurred rather than the one that is easy to test for.

`desk.yml`'s path filter gains `shared/board-rules.json`. Without it the registry could be edited, the Python
half would run and pass, and the Swift half — the one that catches the drift — would never start.

The gate was falsified before it was accepted, three ways: an unbound rule, a drifted value, and a `true`
expectation against a `1`. All three turn both suites red. The first crashed the Swift process on a
force-unwrap and was fixed to assert instead, because a crash fails the build while hiding every rule after it.

## Scope, and what it deliberately leaves alone

- **The columns stay different.** `classify` returns `queue`/`pr_created`/`human_review`; `column(for:)` returns
  `.readyForDev`/`.review`/`.queued` plus ADR 0035's stored stages. [ADR 0011](0011-the-project-board-mirrors-it-never-decides.md) stands: a column is
  computed from git and `gh`, never stored as a decision, and that is as true of a shared fixture as of a
  Projects v2 Status field. The registry covers rules, never column vocabulary — a check written at the wrong seam fails on
  correct divergence, which is how a gate gets switched off.
- **`resolve_base` keeps 0013's declared divergence**: `GitReader.resolveBase` checks local branches for a repo
  with no origin, and `dev.py` does not. Registering it would pin a difference that is deliberate.
- **The merged-head Done rule is not shared, and #79's line asking for it cannot be satisfied as written.**
  `cmd_board` renders open issues into six columns and reads no merged pull requests; it has no Done column and
  no branch-only cards, which is what Dev Desk uses that rule for. Giving `dev board` the rule means giving it a
  Done column, which #79's own "out of scope" forbids. Recorded here rather than left as a criterion nobody can meet.

## Rejected

- **Generate one language from the other.** The seven rules are ~40 lines of regex and sort. A generator, its
  build step and its checked-in output cost more than they remove, and `DeskCore` must stay dependency-free
  ([0016](0016-dev-desk-embeds-a-terminal-with-swiftterm.md), [0036](0036-agents-run-over-a-protocol-and-the-terminal-leaves-the-app.md)).
- **Shell out to `dev board --json`.** Rejected in 0013 on grounds that still hold: its rows carry no PR number,
  no branch name and no Done column, and it needs `python3` and an installed `dev` on `PATH`.
- **A fixture without the registry check.** Simpler, and it would have caught neither real drift. The completeness
  assertion is the part that earns its place.
- **A comment telling the next person to change both.** That is what 0013 shipped. It failed twice.

## Consequences

- A rule added to one reader alone cannot go green. A rule whose value drifts cannot go green.
- A rule that exists in only one reader **and is never registered** is still invisible. The registry raises the
  floor; it does not seal it, and saying so is the point of writing it down.
- `priority_rank` returns the first matching label rather than the best, so `P1, P0` ranks 1. Both readers do
  this identically, so it is agreement, not drift. The registry records it as it behaves; changing it is its own
  ticket, and now a one-line change to one file plus two green suites.
