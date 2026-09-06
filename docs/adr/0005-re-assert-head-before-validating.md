# 0005 — Re-assert HEAD before validating, not only at the start

Status:  Accepted
Date:    2026-08-31
Commit:  2a4a049  ·  PR #23

## Context

`dev:arch` already guarded against a dirty worktree: resolve the SHA before reading, and require
`git status --porcelain` to be empty. That covers half the problem.

`status --porcelain` reports whether the tree is **dirty**. It never reports whether HEAD is still
the commit that was resolved. A branch switch, `pull`, `reset`, a second terminal, or another agent
moves HEAD while leaving `status` perfectly empty — both existing checks pass, every pin resolves,
and the citations describe a commit whose files were never opened.

This is not hypothetical. It happened during the run that produced `0002`–`0004`.

## Decision

Record the SHA once before opening any file, and **re-assert it immediately before `validate`**:

```bash
[ "$(git -C <repo> rev-parse HEAD)" = "$SHA" ] || echo "HEAD MOVED — every read is void"
```

If HEAD moved, **re-read**. Do not re-pin. Bumping the SHA makes the artifact validate and is a lie:
the line numbers came from files opened at the old commit.

## Rejected

- **Trust `status --porcelain` alone** — the previous rule. Blind to a clean tree on a different
  commit, which is the case that actually bit.
- **Re-pin to the new HEAD when drift is detected** — cheaper and wrong. The reads are void; only the
  cited-path test in `0004` can license advancing a pin, and it does not apply when the ranges
  themselves came from different content.
- **Require a lock, or refuse to run on a shared checkout** — heavier than the problem. One
  comparison catches it.

## Consequences

One extra `rev-parse` per run. The failure it prevents is silent and total: an artifact that passes
every check while citing code nobody read.

## Evidence

The drift that produced this, with `status` empty at both ends:

```
shared/entry.md          worktree 272  |  at 98f9216 241
skills/survey/SKILL.md   worktree 290  |  at 98f9216 161
```

A citation of line 244 would have validated green against a different commit, or failed for a reason
that looked like a typo. And the guard, demonstrated:

```
recorded on branch: 1da807f
status: ''                        (empty)
--- switched to main, tree still clean ---
status: ''                        (STILL EMPTY -> old guard passes)
new guard: HEAD MOVED 1da807f -> eba28cb — CAUGHT
```
