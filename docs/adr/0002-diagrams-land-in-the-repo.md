# 0002 — Evidenced diagrams land in `docs/arch/`, with their IR beside them

Status:  Accepted
Date:    2026-08-31
Commit:  eee5597  ·  PR #19

## Context

`dev:arch` wrote only to the session scratch directory, so every artifact evaporated with the
session. The stated reason was diagram rot — a picture reads as authoritative long after it stops
being true — gated on an owner in `dev:docs` that did not exist. That was checked, not assumed:
`grep -in "diagram|\.html|picture" skills/docs/SKILL.md` returned nothing.

That reasoning was written for a diagram that is only a picture. An **evidenced** architecture
diagram pins every component to a file and line range at one commit, so its staleness is detectable
by running something — which prose never offers.

## Decision

`dev:arch` writes `docs/arch/<name>.architecture.json` **and** `<name>.html` into the invoked repo.
Both, always: an HTML with no IR beside it cannot be checked by anything.

`$SCRATCH` remains for `--scratch`, for a target that is not the invoked repo, and for the four
unevidenced diagram types, which nothing can re-check and which must not sit in the tree wearing an
evidenced diagram's authority.

## Rejected

- **Stay in `$SCRATCH` forever** — the original rule. It loses the artifact every session and forces
  a re-run to recover it, and its justification does not survive the diagram being re-checkable.
- **Commit the HTML alone** — the IR is what `dev:docs` re-validates. Without it the artifact is an
  image with a provenance claim nobody can test.
- **Commit diagrams of other repos here** — `docs/arch/` means *this* repo's system. A diagram of
  another checkout goes to `$SCRATCH`.

## Consequences

A committed diagram becomes `dev:docs`'s to keep current, which is the cost. It is paid for by the
gate in `0003`. Artifacts are large (~700 KB of self-contained HTML each) and will accumulate in the
repo's history.

## Evidence

The first artifact under this rule: 20 components, 41 pinned sources, `9/9 artifact checks`. Evidence
verification was negative-controlled — a line past EOF, an absent path and an unknown SHA each fail
with their own rule code (`line-out-of-range`, `file-missing`, `revision-unavailable`).
