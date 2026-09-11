# 0018 — Dev Desk starts the task's agent, by hand or in Auto for queued tasks

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `feat/desk-agents-and-auto`

## Context

Step 1 (ADR 0017) put a shell in each task's folder, started with a click. The developer then asked
for agents as well, with a Manual mode and an Auto mode. In Auto, Dev Desk starts agents for queued
work in parallel, with a warning that this spends tokens.

`dev run` already exists, but it runs agents non-interactively (`claude -p`, `codex exec`). An agent
run that way can't stop at the pipeline's approval gates, Phases 5, 6 and 14.

Parallel agents also can't share one checkout. The pipeline cuts its branch in place, with
`git switch -c <name> --no-track origin/<pre-prod>` (`shared/entry.md:76`). A task in the Queued
column has no branch yet.

## Decision

**What runs, and how.** The Agents tab runs the project's agent interactively in the task's folder.
The agent is Claude Code or Codex: the project's override if one is set, otherwise the app default.
It gets `dev run`'s own prompt: *"Read ~/.claude/skills/dev/SKILL.md and execute it exactly as
written, following every phase and gate it defines."*, with ` Arguments: #N` added while the task has
no branch. The agent stops at the gates and asks in its terminal. Dev Desk adds no flag that skips
permissions or picks a model.

**The folder.**
- **A task with no branch yet gets its own detached worktree** at the base ref, at the task's own
  path. The pipeline cuts the branch there itself.
- **Rule 1b, for shells and agents alike: for a task with no branch yet, a worktree already at the
  task's own path is reused.** For such a task, this replaces ADR 0017's rule 3, which opens a task
  with no branch at the project root. A task that has a branch never uses 1b, because another
  branch's task can share its folder name.

**Manual is the default.** Auto is set per project and is off by default. Turning it on, after the
warning, is the one explicit act that lets Dev Desk start agents without a click per task. Auto
works through the Queued column in board order. It skips tasks that have an agent running, and tasks
it has already started in this session. It keeps at most N agents running across all windows: 3 by
default, adjustable from 1 to 6.

## Rejected

- **`dev run --execute`.** It is non-interactive, so the run can't stop at the gates.
- **`/dev #N` as the prompt.** It isn't a verified Codex form. `dev run`'s prompt is verified for
  both CLIs.
- **`--continue` for resuming.** It isn't a routed argument, and the front door's one-word guard
  stops on it. A bare prompt inside the task's worktree resumes through Entry 0. That holds because
  Entry 0 checks the branch it is on first; until 2026-09-11 it surveyed every branch, and an agent
  started on a merged task did exactly that.
- **Agents at the project root.** Parallel agents would switch branches under each other.
- **Dev Desk cutting the branch.** The pipeline cuts it at the first write, and for a feature only
  after Phase 5.
- **App-wide Auto.** Every opened repository would start agents, untrusted ones included.
- **Restarting a task whose agent exited.** A task that keeps failing would loop and spend tokens.
- **A token estimate in the warning.** There is no reliable source, and the design stores no pricing.

## Consequences

- **Auto spends tokens without a click per task.** The limit and the never-twice rule are the only
  brakes, and Dev Desk can't see usage.
- **Waiting agents count toward the limit.** An agent paused at Phase 5 holds a slot until you answer.
- **The prompt is duplicated from `scripts/dev.py`'s `build_prompt`,** so a change needs both. The board
  rules have the same problem (ADR 0013).
- **Tasks without a number, and fork PRs' tasks, are Manual only.** Auto skips them.
- **Auto does nothing without a GitHub milestone,** because the Queued column comes from the active
  milestone.
- **`dev jobs` and `dev events` are still unbuilt.** So Dev Desk can't tell a working agent from a
  waiting one, can't resume an ended session, and can't show agents side by side in Parallel.
