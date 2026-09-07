# dev-skill

**From GitHub issue to production, with your coding agent.**

A development workflow that investigates problems, plans solutions, writes code, and verifies changes before release. You approve the key decisions: what to build, which approach to take, when to merge, and when to promote to production.

## Install

```bash
git clone https://github.com/hasansa007/dev-skill.git && dev-skill/install.sh
```

This private repository requires GitHub access. The installer links the checkout into existing skill directories for **Claude Code, Codex, and Antigravity**, skipping missing directories. It is safe to rerun.

Reload skills with `/reload-skills` in Claude Code, or restart your CLI. Check the loaded skill list.

## Start a task

```text
/dev #496
/dev fix the course list losing its scroll position
```

Bare `/dev` shows current issues and suggested next work. Examples use Claude Code syntax; see the guide for other CLIs and dependencies.

![The dev workflow, from discovery to production](assets/dev-journey.gif)

## Learn more

- [User guide](documentation/GUIDE.md) — usage, compatibility, and troubleshooting.
- [Commands](documentation/COMMANDS.md) — every command and its purpose.
- [Workflow](documentation/WORKFLOW.md) — phases, approvals, and known limitations.
- [Contributing](documentation/CONTRIBUTING.md) — structure, design rules, and maintenance.
