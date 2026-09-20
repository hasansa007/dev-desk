# 0010 — Paths point at the install root, not the clone

Status:  Accepted, amended by [0054](0054-the-install-root-is-one-hidden-symlink-not-a-skills-directory.md)
Date:    2026-09-10
Commit:  ea912ba  ·  `feature/tracker-and-pipeline-state`

## Context

14 files hardcoded `~/Developer/skills/dev-skill/…` — `SKILL.md` alone 9 of 33 occurrences. The
pipeline's first instruction was to read a file under one developer's home directory, so the family
could not run on any other machine.

The obvious fix — make them relative — would have reverted documented scar tissue. `dev:survey`
Phase 2 states it outright: *"the absolute path, because this skill runs inside somebody else's
repo, where a bare `shared/entry.md` resolves to a file that does not exist."* `dev:arch` Phase 0
carries the same. **Absolute was the fix; the home-directory prefix was the accident.**

## Decision

Use the **install** path: `~/.claude/skills/dev/…`.

`install.sh` already symlinks the clone into each CLI's skills directory under the fixed name `dev`,
so that path resolves identically on any machine regardless of where the repo was cloned. 31
occurrences across 13 files swapped; the convention is documented once in `SKILL.md` and once in
`shared/entry.md`, naming the Codex and Antigravity roots.

Verified 2026-09-10: all three symlinks present, and `shared/entry.md`, `shared/pipeline.md`,
`mobile/MASTER_PROMPT.md`, `web/FEATURE_PROMPT.md` and `hooks/pr-gates.sh` all resolve through the
new root.

**Consequence accepted:** a clone that has never been installed has no root, so `install.sh` is now
required rather than convenient. Stated in both notes.

## Rejected

**Anchor to the file — `<root>` is two levels up from this `SKILL.md`.** Elegant, survives any
install location, needs no installer. Lost because it depends on the agent tracking where it loaded
the file from, which was **unverified** — and the existing scar says a bare relative path already
failed once. Betting 33 edits on an untested assumption to avoid one that is provably true was the
worse trade. Worth revisiting with a real test.

**Have `install.sh` copy-and-substitute a `{{SKILL_ROOT}}` token instead of symlinking.** Always
literally correct, zero inference. Lost because it abandons the symlink, so edits to the clone stop
taking effect until the installer is re-run — it would break the workflow of the person developing
this family.

## Later (2026-09-11)

The rule stands; two of the paths verified above moved, with nine others, when files started living
with the flow that reads them ([ADR 0015](0015-files-live-with-the-flow-that-reads-them.md)). The
new install paths:

- `~/.claude/skills/dev/platforms/web/` — `MASTER_PROMPT.md`, `FEATURE_PROMPT.md`, `pipeline-web.md`
- `~/.claude/skills/dev/platforms/mobile/` — `MASTER_PROMPT.md`, `FEATURE_PROMPT.md`, `pipeline-{ios,android,kmp}.md`
- `~/.claude/skills/dev/skills/prod/` — `prod-secrets.md`, `prod-secrets-apple.md`
- `~/.claude/skills/dev/skills/audit/` — `compliance_auditor.py`

The Decision above keeps the paths as they were on 2026-09-10.
