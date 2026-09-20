# Command reference

Every door, what it takes, what it gives back, and how it is typed. New here?
Start with [Getting started](GETTING-STARTED.md).

Examples use Claude Code syntax. For other agents, see [CLI compatibility](GUIDE.md#running-it-on-another-cli).
Installed as a plugin, every door is namespaced — the root door is `/dev:dev`, not `/dev`.

## Start or capture work

| Command | Purpose |
| --- | --- |
| `/dev` | Orient: detect where the repo is and offer the two or three doors that fit. Read-only. |
| `/dev <issue or description>` | Start the full development workflow. |
| `/dev:create-issue` | File a work item for later. |
| `/dev:create-bug` | File a bug report without implementing the fix. |
| `/dev:create-epic` | File a parent epic; split it during planning. |
| `/dev:board` | Show current work, the queue, next tasks and statistics; move, cancel or delete a card. |
| `/dev:findings` | Inspect an app for defects and architectural drift; file the confirmed. |
| `/dev:ideation` | Inspect an app for performance, security and quality opportunities; file the confirmed. |
| `/dev:roadmap` | Propose themes from the repo's own evidence; write milestones and epic parents. |
| `/dev:insights` | Answer a question about the codebase with citations; keep what lasts in `PROJECT_MAP.md`. |

```text
/dev
/dev:board
/dev #496
/dev:create-bug the course list loses its scroll position
/dev:findings
/dev:ideation
/dev:roadmap
/dev:insights
```

Bare `/dev` **orients**: one detection pass over the repo, then the two or three doors that fit it —
resume a branch with work on it, open the board when the tracker is stocked, stock an empty tracker,
or say what a fresh project is still missing. It is read-only: it never cuts a branch and never
starts work.

`/dev:board` is the board itself. It shows the queue, what is in flight and what is next, then asks.
Its writes are bounded: move a card, cancel it with a reason, or delete it behind a hard gate.

Findings writes provenance into each issue's `## Suspected` section. Its code inspection does not
replace runtime verification.

## Continue delivery

| Command | Starting point | Result |
| --- | --- | --- |
| `/dev:verify` | An existing branch | Verification evidence, followed by documentation checks |
| `/dev:docs` | A diff | Documentation and decision checks; PR `## DOCS` content |
| `/dev:code-review` | A branch | Verified review findings, spec-compliance and security passes; Phase 13's gate |
| `/dev:pre-prod` | A branch ready for delivery | PR preparation, review gates, and an approved merge |
| `/dev:review` | A PR with feedback | Addressed feedback and a return to the merge stage |
| `/dev:prod` | Verified pre-production work | Production checks and an approved promotion |
| `/dev:rollback` | A broken production release | Change classification, safe revert with dual-branch sync, and audit trail |
| `/dev:audit` | A branch or PR | Mechanical phase compliance audit against execution evidence |

```text
/dev:verify
/dev:docs
/dev:code-review
/dev:pre-prod
/dev:review https://github.com/you/repo/pull/123
/dev:prod
/dev:rollback
/dev:rollback <sha>
/dev:audit
/dev:audit <pr-number>
```

These commands let you resume from durable work across sessions. A full `/dev` run already includes
the delivery stages; you do not need to call each command manually. Verification continues into
documentation checks; merges and production promotion require approval.

`/dev:rollback` classifies the broken promotion (code-only vs migration), proposes a safe revert with
dual-branch sync, and pauses for human approval before executing.

`/dev:audit` mechanically cross-references reported `## PIPELINE` claims against tool-call and
repository evidence, detects hidden skips, and appends a `## COMPLIANCE` report.

`/dev:code-review` is Phase 13. It uses the separate `code-review` integration as its engine and adds
the spec-compliance and security passes around it.

## App and maintenance tools

| Command | Purpose |
| --- | --- |
| `/dev:launch` | Build and launch the app. |
| `/dev:launch-kill` | Stop this project's servers started by the launch workflow. |
| `/dev:shots` | Capture screens from the running app. |
| `/dev:comment-budget` | Report comments and docstrings that exceed the documentation budget. Add `--apply` to make changes. |
| `/dev:arch` | Generate a diagram tied to verified source locations. Requires Archify. |

```text
/dev:launch
/dev:shots
/dev:arch the dev family
/dev:launch-kill
```

The tools operate independently of pipeline phases. `launch-kill` and `shots` reuse launch procedures
instead of duplicating them.

## `dev` — the optional helper

A stdlib-only Python helper for the parts that are computable rather than judged. Every command above
works without it; when present, the doors use it instead of doing the same work by hand.

| Command | Purpose |
| --- | --- |
| `dev doctor` | Check the environment: repo, origin, base branch, `gh` auth, install root. |
| `dev board [--json]` | Classify open issues into columns from git and `gh`. |
| `dev state checkpoint\|read\|verify` | Record which pipeline phase a branch reached; `verify` fails when the record disagrees with git. |
| `dev project [--number N] [--apply]` | Mirror the computed board into a GitHub Project v2 board. Dry run unless `--apply`. |
| `dev run <door> [args]` | Dispatch a door to an agent CLI for headless or CI use. Prints the command unless given `--execute`. |

```bash
python3 ~/.claude/.dev-root/scripts/dev.py doctor
```

`install.sh` puts `dev` on your `PATH` by linking it into `~/.local/bin` (or `~/bin`) when one of
those is already on your `PATH`. It never edits your shell profile and never replaces a `dev` that
belongs to another tool — if it can't link, it says so and prints the alias to use instead.

[User guide](GUIDE.md) · [Pipeline details](WORKFLOW.md)
