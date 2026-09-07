# Command examples

The full [command reference](../README.md#commands) is in README.

Examples use Claude Code syntax. For other agents, see [CLI compatibility](GUIDE.md#running-it-on-another-cli).

## Start or capture work

```text
/dev #496
/dev:create-bug the course list loses its scroll position
/dev:survey
```

Survey writes provenance into each issue's `## Suspected` section. Its code inspection does not replace runtime verification.

## Continue delivery

```text
/dev:verify
/dev:docs
/dev:review https://github.com/you/repo/pull/123
```

These commands let you resume from durable work across sessions. A full `/dev` run already includes the delivery stages; you do not need to call each command manually.

`/code-review` is a separate integration used during review. It is not a member of the `dev` command family.

## App and maintenance tools

```text
/dev:launch
/dev:shots
/dev:arch the dev family
/dev:launch-kill
```

The tools operate independently of pipeline phases. `launch-kill` and `shots` reuse launch procedures instead of duplicating them.

[User guide](GUIDE.md) · [Pipeline details](WORKFLOW.md)
