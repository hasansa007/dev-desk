# 0003 — The diagram staleness probe bumps the revision to HEAD

Status:  Accepted
Date:    2026-08-31
Commit:  eee5597  ·  PR #19 (the reasoning's own commit, `a152772`, was squashed away)

## Context

`0002` made committed diagrams `dev:docs`'s responsibility, so `dev:docs` gained a check: re-run
`archify validate --repo-root .` over every `docs/arch/*.architecture.json` and fail the gate when a
pin no longer resolves.

**That check was tautological.** An IR's `meta.repository.revision` names a commit that still exists,
and the cited files still exist *at that commit*, so it returns `ok` no matter what the branch did to
them. It was caught by running it rather than reading it: renaming a cited file and re-running the
loop on the committed IR returned `ok`.

A gate that always passes is indistinguishable from a gate that passes because things are fine —
which is the exact failure this skill exists to catch elsewhere.

## Decision

Probe a **copy** of the IR with `meta.repository.revision` set to the branch's HEAD. Never rewrite
the committed IR's revision to make a check pass: that pin records the commit at which someone
actually read the code.

Run it over every `docs/arch/*.architecture.json` in the repo, not only those the branch touched —
any diff can move a file some other diagram cites.

## Rejected

- **Validate the committed IR as pinned** — the original. Always passes; see above.
- **Bump the committed IR's revision on every branch** — makes the artifact validate and is a lie.
  The line numbers came from files opened at the old commit. Advancing a pin is legitimate only under
  the cited-path test in `0004`.
- **Check only the diagrams the branch touched** — misses the common case, where a diff moves a file
  that a diagram the branch never opened happens to cite.

## Consequences

The probe catches a moved, renamed or deleted file. It **cannot** catch a pure line shift — an insert
above a cited range moves it while every pin still resolves. That gap is closed separately by the
cited-path intersection check, and the residue after both is structural: a diagram whose pins all
resolve while the shape it draws is wrong. Only a person catches that.

## Evidence

```
# committed IR, as pinned, after renaming a cited file:
ok architecture ... 0 errors, 0 warnings          <-- proves nothing

# same rename, revision bumped to HEAD:
[repository-evidence/file-missing] ...
```

Verified three ways — clean tree / cited file renamed / reverted → **OK / STALE / OK**.
