# Using dev-skill

Start with a task, let the agent investigate, and agree on the approach before it writes code.

[Commands](COMMANDS.md) · [Workflow](WORKFLOW.md) · [Contributing](CONTRIBUTING.md)

## Start a task

In Claude Code:

```text
/dev #496
/dev fix the course list losing its scroll position
```

An issue number, issue URL, or plain description starts the workflow. Bare `/dev` shows the issue tracker and suggested next work.

To capture work without implementing it, use `/dev:create-issue`, `/dev:create-bug`, or `/dev:create-epic`.

## Choose the depth

The agent proposes a tier; you can override it.

| Tier | Typical use | Check depth |
| --- | --- | --- |
| Light | Small fixes and copy changes | Tests and a quick diff review |
| Standard | Features spanning several files | Adds a real live check |
| Deep | Authentication, payments, migrations, major refactors | Full verification evidence and security review |

Light is the default. Say “go deeper” when the task needs more scrutiny.

## Discuss the approach

Before implementation, the agent asks for your approach and discusses scope. This is where you can change direction, clarify the UI, or split an epic into smaller tasks.

Architecture choices, merges, and production promotion have their own decision points. The agent announces the next phase when it stops.

## Continue existing work

You can start from an existing branch, diff, or PR:

```text
/dev:verify
/dev:docs
/dev:review https://github.com/you/repo/pull/123
```

Verification continues automatically into documentation checks. Release actions require approval. See [all commands](COMMANDS.md) for the other entry points.

## Running it on another CLI

The installer links this checkout into existing skill directories for Claude Code, Codex, and Antigravity. It skips missing directories and does not install dependencies.

The workflow is Markdown, but Claude Code's slash commands and hooks do not transfer automatically. In another CLI, point the agent at `SKILL.md` for a full run or `skills/<name>/SKILL.md` for a focused command.

- Provide the required `superpowers:systematic-debugging` and `superpowers:brainstorming` skills, or suitable equivalents that preserve their gates.
- Adapt Claude Code hooks to the host agent when equivalent enforcement is needed.
- Provide the project's build and verification tools. Optional integrations are described in the relevant procedures.
- Survey can inspect flows sequentially when subagents are unavailable.
- Architecture diagrams require [Archify](https://github.com/tt-a1i/archify).

After installation, reload skills or restart the agent and check its loaded skill list.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| Too much process | Ask for “Light tier.” |
| Moving too quickly | Ask it to slow down or pause between phases. |
| Wrong direction | Correct the scope during the discussion before building. |
| A check was skipped | Ask why and inspect `Skipped:` in the PR's `## PIPELINE` section. |
| Skill is not available | Check the loaded skill list, installation output, and CLI invocation. |

Read [workflow limitations](WORKFLOW.md#known-gaps) before relying on a gate as an automated guarantee.
