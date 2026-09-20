# hooks/

Four Claude Code hooks — the mechanical half of six phases. **Installed by the plugin** (`hooks.json`,
below). A symlink install from `install.sh` does not carry them: hooks are harness config, so that
path still needs its own two settings blocks.

They live here for the reason `pr-gates.yml` does: beside the rules they enforce. `pr-gates.sh`
greps `^## PIPELINE`, `teardown.sh` mirrors Phase 11's kill commands, `context-load.sh` parses
PROJECT_MAP's headings. Rename any of those in `shared/` and the hook is right there, visibly stale
— instead of drifting unnoticed in `~/.claude/`.

`pr-gates.yml` is not a hook. It is the CI template for *other* repos (its header says how to
install it there), kept beside `pr-gates.sh`, which mirrors its PR-body check. Only the four `.sh`
files are linked into `~/.claude/hooks/` (below).

## What a hook can and cannot do

A hook checks **presence of state at a tool boundary**. That is the whole of it, and it lands on a
seam this repo already drew: Phases 1–8 pass reasoning rather than artifacts (`SKILL.md`), which is
why they have no `dev-*` door — and why they have no hook either. A phase that can be a door can
usually be a hook; a phase that cannot, cannot.

Phase 12 states the ceiling outright: *"the check is ACCURACY, not presence."* `pr-gates.sh` proves
`## DOCS` exists. Nothing here can prove the paragraph around your edit is still true.

## The four

| Hook | Phase | Event | Verdict |
|---|---|---|---|
| `branch-guard.sh` | 3 | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit`, and `Bash` for `git commit` / `git -C <dir> commit` | **deny** a write while on `main`/`master`/`staging`, judged in the folder the command runs in — not the session's; this repo is exempt |
| `pr-gates.sh` | 12 · 14 · 16 | PreToolUse `Bash` | **deny** a PR body missing `## PIPELINE`/`## DOCS` · **deny** a push onto a protected ref · **ask** on a merge into prod, on the documented catch-up push, and on `.dev/` phase state that disagrees with git |
| `teardown.sh` | 11 | Stop | **block the stop** while MCP debug Chrome is alive |
| `context-load.sh` | 1 | SessionStart | inject PROJECT_MAP's `TECH_STACK` + `ORPHANS` and the branch |

Phase 11's *checklist* is not reachable — only its teardown rule is.

## Install

**The plugin installs all four, and is the way to do it.** `hooks/hooks.json` wires every hook to its
event with `${CLAUDE_PLUGIN_ROOT}`, so they travel with the repo and need no settings block and no
symlink into `~/.claude/hooks/`:

```text
/plugin marketplace add ~/Developer/skills/dev-desk
/plugin install dev@dev-desk
```

This makes `branch-guard.sh` **global**, which the per-repo section below was written to avoid. That
argument expired on 2026-09-19: the hook now exempts the repo it lives in and judges the folder the
command runs in, so a global install no longer blocks the commits here or in an unrelated repo. What
it does mean is that every repo you work in gets the protected-branch rule — which is the point.

The two sections below are the manual path, for a symlink install (`install.sh`) or a CLI without
plugins.

**Per-repo — `branch-guard.sh` only**, in repos with a two-stage flow. Still not global, but no longer
because of *this* repo: since 2026-09-19 the hook exempts the repo it lives in, so a global install
would not block the commits here. It stays per-repo because a two-stage flow is a per-repo fact — a
repo without `staging` has no branch worth denying.
`<repo>/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/branch-guard.sh", "timeout": 10 }] },
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/branch-guard.sh", "timeout": 10 }] }
    ]
  }
}
```

**Global — the other three**, in `~/.claude/settings.json`:

```json
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/pr-gates.sh", "timeout": 15 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/teardown.sh", "timeout": 10 }] }
    ],
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/context-load.sh", "timeout": 10 }] }
    ]
  },
  "attribution": { "commit": "", "pr": "" },
```

`attribution` is not a hook. It retires the two Universal Rules forbidding `Co-Authored-By` and the
AI footer — the harness strips them, so they cannot be forgotten.

Then point `~/.claude/` at this repo, so edits here take effect without a copy step:

```bash
for f in branch-guard pr-gates teardown context-load; do
  ln -sfn ~/.claude/.dev-root/hooks/$f.sh ~/.claude/hooks/$f.sh
done
```

## The log — this is the point

Every hook appends to `~/.claude/hooks/fired.log`, **pass and deny alike**:

```bash
awk -F'\t' '{print $2, $3}' ~/.claude/hooks/fired.log | sort | uniq -c | sort -rn
#   214 pr-gates      pass
#     9 branch-guard  deny
#     1 pr-gates      bypass
```

This is `## PIPELINE`'s `Gates:` line, for the hooks themselves. *How to propose a change* in
`docs/guide/CONTRIBUTING.md` makes deletion safe only with evidence — and a hook that denies silently supplies none,
which would put pruning back on nerve. A hook reading `pass` two hundred times and `deny` zero is
retirable on data.

## Bypass

```bash
touch <repo>/.claude/hooks-off      # every hook honours it, and LOGS the bypass
```

`pr-gates.yml` already says it: *a check that fires on correct work is how a check gets ignored.*
In CI that costs you a red X; here you can delete the file outright. So the escape hatch has to be
cheaper than deletion, and visible in the log when used. Every deny message ends with the override
line.

## Scar tissue vs design

Dated = paid for by a real failure (`docs/guide/CONTRIBUTING.md`, principle 1). All three below were found by the
falsification pass, not by the happy path.

- **2026-08-05 — `teardown.sh` counts the LAUNCH FLAG, not the profile path.** The first version
  grepped `chrome-devtools-mcp/chrome-profile`, which also matches Phase 11's own teardown command
  *and* every `chrome-devtools-mcp` node server. Twelve MCP servers were live on the machine at the
  time: it would have blocked every Stop, forever. Now `--user-data-dir=…/chrome-profile`, plus an
  exclusion of the hook's own process tree.
- **2026-08-05 — `branch-guard.sh` uses `git branch --show-current`.** `rev-parse --abbrev-ref HEAD`
  fails on an unborn branch, so the first write into a fresh repo's `main` passed silently.
- **2026-08-05 — `^## PIPELINE` stays anchored.** Inherited from `pr-gates.yml`, whose unanchored
  grep passed a body whose heading had been deleted because the string appeared in prose.

- **2026-09-19 — `branch-guard.sh` judges the folder the COMMAND runs in, not the session's.** The
  first real-run failure, and the most expensive: a `Bash` commit was judged by the session's starting
  folder, so while one project sat on `staging` the guard denied commits in *other* repos and in
  `~/.devdesk/wt` worktrees — and it blocked dev-desk itself, whose `CLAUDE.md` says the pipeline does
  not gate it. With Dev Desk's hook forbidding a project folder's branch switch, that deadlocked every
  commit in a session (2026-09-18/19). Now the target is resolved from each `git -C` target, then a
  `cd` on the first line, first real directory winning — so a commit message quoting a path cannot
  steer it — `git -C <dir> commit` is recognised as a commit at all, and the repo the hook lives in is
  exempt. Nine cases tested.

**Undated, therefore unproven:** everything else — the phase-to-event mapping, the ask/deny split on
pushes, the bypass, the log format. Twenty pipe-tested payloads and, as of 2026-09-20, **one real
failure found in use** — the 09-19 entry above. The other three hooks still have zero real runs behind
them.

## Known limits

- A `PreToolUse` deny stops the *tool call*, not the intent. Nothing prevents rerouting an edit
  through `python3 -c`. These raise the floor; they do not seal it.
- `pr-gates.sh` sees the command string and `--body-file`. A body arriving any other way is unseen.
- `^## PIPELINE` is line-anchored, so a body whose first heading sits on the same line as `--body "`
  would false-deny. The Phase 14 template never produces that shape.
- The merge check calls `gh pr view` to read the base branch; when that fails it **asks** rather
  than passing, because the prod path is the expensive one to get wrong.
- `teardown.sh` exits 0 when `stop_hook_active` is true. One block per turn, never a loop.
