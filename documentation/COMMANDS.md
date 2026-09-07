# Commands

Examples use Claude Code syntax. For other agents, see [CLI compatibility](GUIDE.md#running-it-on-another-cli).

## Start or capture work

| Command | Purpose |
| --- | --- |
| `/dev` | Show current issues and suggested next work. |
| `/dev <issue or description>` | Start the full development workflow. |
| `/dev:create-issue` | File a work item for later. |
| `/dev:create-bug` | File a bug report without implementing the fix. |
| `/dev:create-epic` | File a parent epic; split it during planning. |
| `/dev:issues` | Show current work, next tasks, and statistics. |
| `/dev:survey` | Inspect an app and file confirmed findings. |

```text
/dev #496
/dev:create-bug the course list loses its scroll position
/dev:survey
```

Survey writes provenance into each issue's `## Suspected` section. Its code inspection does not replace runtime verification.

## Continue delivery

| Command | Starting point | Result |
| --- | --- | --- |
| `/dev:verify` | An existing branch | Verification evidence, followed by documentation checks |
| `/dev:docs` | A diff | Documentation and decision checks; PR `## DOCS` content |
| `/dev:pre-prod` | A branch ready for delivery | PR preparation, review gates, and an approved merge |
| `/dev:review` | A PR with feedback | Addressed feedback and a return to the merge stage |
| `/dev:prod` | Verified pre-production work | Production checks and an approved promotion |

These commands let you resume from durable work across sessions. A full `/dev` run already includes the delivery stages; you do not need to call each command manually.

`/code-review` is a separate integration used during review. It is not a member of the `dev` command family.

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

The tools operate independently of pipeline phases. `launch-kill` and `shots` reuse launch procedures instead of duplicating them.

[User guide](GUIDE.md) · [Pipeline details](WORKFLOW.md)
