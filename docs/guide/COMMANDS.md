# Command examples

The full [command reference](../../README.md#commands) is in README. New here? Start with [Getting started](GETTING-STARTED.md).

Examples use Claude Code syntax. For other agents, see [CLI compatibility](GUIDE.md#running-it-on-another-cli).

## Start or capture work

```text
/dev
/dev:kanban
/dev #496
/dev:create-bug the course list loses its scroll position
/dev:findings
/dev:ideation
/dev:roadmap
/dev:insights
```

Bare `/dev` routes to `/dev:kanban` — the board. It shows the queue, what is in flight and what is
next, then asks. Its writes are bounded: move a card, cancel it with a reason, or delete it behind a
hard gate. It never cuts a branch and never starts work.

Findings writes provenance into each issue's `## Suspected` section. Its code inspection does not replace runtime verification.

## Continue delivery
 
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

These commands let you resume from durable work across sessions. A full `/dev` run already includes the delivery stages; you do not need to call each command manually.

`/dev:rollback` classifies the broken promotion (code-only vs migration), proposes a safe revert with dual-branch sync, and pauses for human approval before executing.
`/dev:audit` mechanically cross-references reported `## PIPELINE` claims against tool-call and repository evidence, detects hidden skips, and appends a `## COMPLIANCE` report.

`/dev:code-review` is Phase 13. It uses the separate `code-review` integration as its engine and adds the spec-compliance and security passes around it.

## App and maintenance tools

```text
/dev:launch
/dev:shots
/dev:arch the dev family
/dev:launch-kill
```

The tools operate independently of pipeline phases. `launch-kill` and `shots` reuse launch procedures instead of duplicating them.

[User guide](GUIDE.md) · [Pipeline details](WORKFLOW.md)
