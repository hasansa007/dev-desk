# 0054 — The install root is one hidden symlink, not a skills directory

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Amends [0010](0010-paths-point-at-the-install-root.md) and the rule stated in the root `SKILL.md` since the family began: that every absolute path in it
resolves under a per-CLI skills directory. It does not reverse *absolute paths* — that rule
([the "Where these paths point" section](../../SKILL.md)) stands and is the reason this fix was
needed at all.

## Context

Every door reads the shared contracts by absolute path — `shared/entry.md` sixteen times, the
pipeline phases dozens more, 68 reads across 21 files. The path was
`~/.claude/skills/dev/...`, created by `install.sh` symlinking the clone into each CLI's skills
directory.

A Claude Code **plugin** creates no such link. Its files live in
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, a path that contains a version and
changes on every update. So the first plugin install (2026-09-20) removed the symlink, and all 68
reads pointed at a directory that no longer existed. Nothing failed loudly: the doors would simply
have found no contract.

`${CLAUDE_PLUGIN_ROOT}` does not solve it. The harness substitutes it into hook *commands*; it is
**not** exported to a tool call, so `${CLAUDE_PLUGIN_ROOT:-~/.claude/skills/dev}` in a door's prose
always takes the dead fallback. Verified before relying on it.

## Decision

**1. One root: `~/.claude/.dev-root`.** A symlink to whichever copy of the repo is live. All 68
reads move to it.

**2. Both installs maintain it.** `install.sh` writes it on every run, for every CLI. The plugin
writes it from `hooks/context-load.sh` at SessionStart, deriving its own location from `$0` rather
than from an environment variable that is not there.

**3. It is hidden and outside `~/.claude/skills/`.** A root under `skills/` is scanned, and the
doors would be listed a second time beside the plugin's — observed immediately when the root was
first placed at `~/.claude/dev`. The leading dot keeps it out of any directory walk.

**4. The per-CLI links stay.** `~/.claude/skills/dev/`, `~/.codex/skills/dev/` and Antigravity's
registered path are still how a CLI *finds* the doors. What a door *reads* is the root.

## Consequences

- The family now installs three ways — symlink, plugin, or both — and resolves the same either way.
  Codex and Antigravity get the root from `install.sh` even though they have no plugin system.
- A machine with neither install has no root, and the doors cannot run. That was already true.
- `install.sh` now creates `~/.claude` if absent, since a Codex-only machine may not have it.
- The root is refreshed, not assumed: `context-load.sh` compares the existing link before writing,
  so a plugin update to a new version directory corrects it at the next session start.
