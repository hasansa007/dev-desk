# App and CLI: task continuity and parallel work

**Date:** 2026-09-11

**Status:** both entry paths and separate project windows accepted; implementation details remain proposed

**Related:** [container draft](2026-09-11-container-design.md) ·
[findings and existing issues](2026-09-11-findings-and-existing-issues-design.md) ·
[navigation and Insights](2026-09-11-mac-app-navigation-and-insights-design.md)

## Accepted product direction

Support both starting work through the desktop app or `dev`, and connecting work started
outside them. The maintainer explicitly chose both paths. Where work starts must not force
the developer to abandon its requirements, branch, evidence, or decisions when changing surfaces.

The app may display several task terminals together. Parallel work is organized around
individual tasks with their own requirements and working environments, not anonymous terminals.
This records the product direction; it does not claim that external session attachment is
implemented or universally supported by agent CLIs.

## Accepted project window direction

The maintainer chose opening projects in separate Mac windows. Keep each project's tasks,
findings, decisions, and terminal panes scoped to its window. Parallel task/session views belong
inside that project window. Closing a project window must not implicitly stop managed agents;
reopening reconnects to available execution records rather than automatically launching copies.
The project picker/opening flow and detailed window restoration behavior remain proposed UI work.

## Proposed responsibility model

| Object | Responsibility |
|---|---|
| Task | Goal, requirements, acceptance criteria, issue and finding links |
| Workspace | Repository, branch, checkout path, and isolation for code changes |
| Agent session | Provider-specific conversation, context, and execution |
| dev-desk | Investigation, planning, verification, review, and decision procedures |
| Shared runner | Managed process/session lifecycle and coordinated input |
| App and CLI | Views and actions over the same task and runner records |

A terminal is a view into execution, not the identity of a task. Task identity must survive
branch renames, session replacement, and closing a view. One task can have several sessions
over time. A new view must not silently create a second agent process.

## Path 1: managed start

Starting from the app or `dev` uses the same runner. Record task identity, requirements,
workspace, agent, and available session identifier when starting. Both surfaces can then
locate the task, show its evidence and progress, and send input through the shared runner.

Closing a view must not implicitly stop managed work. Explicit Stop is a separate action.
Process survival, restart recovery, and interruption behavior need a concrete runner contract.

## Path 2: connect existing work

Offer an explicit action to connect an existing checkout/branch to a task. Discover candidate
work without claiming that a branch identifies its agent conversation. Preserve the existing
branch, working directory, and uncommitted changes; do not automatically relocate or restart it.

Represent the available capabilities explicitly:

| Connection level | Available behavior |
|---|---|
| Repository tracking | Show changes, PRs, and available artifacts without session control |
| Resumable session | Continue an ended turn using a verified provider-specific session mechanism |
| Live connection | View and interact with the existing running process through a supported transport |

Resuming must not create a second process competing with a still-running session.
Verify session/workspace association before resuming.
These are capability descriptions, not a promise that every provider supports every level.
The app must not offer unsupported input or resume controls.

If the original session cannot be continued, offer a new session with an explicit handoff:
requirements, acceptance criteria, decisions, current changes, verification evidence, and next
action. Label it as a new session; do not claim the original conversation was restored.

## Continuation semantics

- **Attach:** connect another view to execution that is still running.
- **Resume:** continue a provider session after its previous turn ended.
- **Handoff:** start a new session from durable task artifacts, possibly with another provider.

Several views may observe one session. Input must be serialized through one control path,
with protection against duplicate resumes and answers to obsolete questions. For externally
started work without a coordinated input mechanism, remain at the supported connection level.
Phase checkpoints alone cannot establish session ownership or readiness for input.

## Parallel work and terminals

Recommended first model: each independent task has a primary agent, its own branch, and an
isolated checkout, usually a git worktree. Multiple tasks can execute concurrently while each
checkout has one mutating execution owner. Respect a project's checkout conventions; if isolation
is unavailable, serialize conflicting work instead of running writers together silently.

Within a task, show requirements, branch, changes, evidence, and sessions. Allow task terminals
side by side. Supporting reviewers and verification agents belong under the task, with their
logs available on demand; a separate permanent terminal for every helper is unnecessary.

### Proposed agent interaction surface

Show agents under their task with role, assignment, execution state, workspace, and connection
capabilities. Selecting an agent opens the output that is actually available: an interactive
terminal, structured activity, or a completed result. Do not label structured logs as an
interactive terminal or promise visibility into unavailable provider-internal execution.

- An independent managed agent session can expose terminal attachment and session continuation
  when its adapter supports them. Opening its view must not start a duplicate execution.
- A delegated helper may expose only progress and a result, with no independent terminal or
  resumable session. Expose direct interaction only when the provider supports it; otherwise
  route follow-up work through the task's coordinating agent or an explicit new assignment.
- A running session offers View, plus supported input or interruption controls. An ended turn
  offers Continue when resumable. A completed helper offers its result and a follow-up request.
- A new session created from artifacts is an explicit handoff, never described as restoration
  of the original agent conversation. Multiple code writers still need workspace ownership.

Suggested controls are Open terminal, View activity, Continue, and Request follow-up, shown by
capability and state. The agent list should support opening two available outputs side by side.
Exact terminal transport, provider support, and coordinator routing remain unverified design work.

Multiple coding agents within one task need additional file ownership or checkout isolation
and an integration owner. A task branch alone does not prevent concurrent working-tree edits.
This deeper coordination remains a later design question, not a prerequisite for independent
tasks to run in parallel.

Track dependencies between tasks. Isolation does not guarantee compatible integration: after
one task merges, reassess another task against the updated base and re-run affected checks.
Do not infer dependency merely from shared files, or readiness merely from an agent's exit code.

## Recommended delivery order

1. Shared managed start and task lookup from app and CLI, with isolated task workspaces.
2. Connect existing work for repository tracking and explicit artifact-based handoff.
3. Add external session resume and live connection per provider after verifying capabilities.

Both entry paths are part of the product scope. This order is a recommendation for delivery,
not permission to claim full external-session control in the first increment.

## Next unresolved contract

Define durable task/workspace/session identities and their ownership before fixing CLI verbs
or UI behavior. Establish how both surfaces discover the same record, reconnect after restart,
coordinate input, and distinguish stale process records from active execution. Task and finding
identity must also join the issue/evidence model without creating another authoritative backlog.

Proposed acceptance scenarios: start from either managed surface and open from the other without
duplicating execution; reconnect an external checkout without changing files; display an unsupported
session honestly; reject duplicate resume or stale input; run two isolated tasks concurrently;
recover task context after a session becomes unavailable. These checks have not been implemented.

This document changes no runtime behavior or skill instructions and does not settle the one-repo
versus two-repo question.
