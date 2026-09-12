# Dev Desk

Dev Desk is a native Mac app for the dev-skill family. For each project it shows the board, a workspace for every task, findings, the roadmap and decisions, with Insights alongside. Each task also gets a real shell and its agent, running in the task's own folder.

It's a first build of the container described in the [container spec](../../docs/superpowers/specs/2026-09-11-container-design.md). [System model](../../docs/guide/SYSTEM-MODEL.md) explains what it reads, what it runs, and what isn't built yet.

## Download

A prebuilt release is quicker than building. Releases are ad-hoc signed zips, published to GitHub Releases when a `desk-v*` tag is pushed:

```bash
gh release download -R hasansa007/dev-skill -p 'Dev-Desk-*.zip'
unzip -o "Dev-Desk-"*.zip -d /Applications
```

The first launch needs one extra step, because the app isn't notarized: right-click **Dev Desk.app** and choose **Open**, or run `xattr -dr com.apple.quarantine "/Applications/Dev Desk.app"`. It needs macOS 14 or later.

## Requirements

- macOS 14 or later, and Xcode.
- `xcodegen` (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't committed.
- Network access for the first build. It fetches SwiftTerm 1.11.2, the app's one dependency ([ADR 0016](../../docs/adr/0016-dev-desk-embeds-a-terminal-with-swiftterm.md)).
- Optional:
  - `gh auth login`, for GitHub data (issues, PRs and milestones);
  - `claude` or `codex` on your login shell's `PATH`, to run agents.

## Build and run

To install the app where you actually open it — `~/Applications` — and launch it:

```bash
apps/desk/install.sh            # add --no-open to install without launching
```

Everything else builds into DerivedData, which is a **different bundle** from the installed one. That
distinction has already cost a session: changes were built, launched and verified in DerivedData
while the installed copy — the one being opened from Spotlight — stayed untouched and correctly
appeared not to change. `install.sh` builds Release ad-hoc signed, exactly as `desk-release.yml`
does, replaces `~/Applications/Dev Desk.app`, and prints the installed binary's timestamp so you can
see which build you have.

For development in Xcode:

```bash
cd apps/desk && xcodegen generate && open DevDesk.xcodeproj   # then ⌘R in Xcode
```

Or without Xcode's window:

```bash
cd apps/desk && xcodegen generate
xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-dd build
open "/tmp/devdesk-dd/Build/Products/Debug/Dev Desk.app"
```

## Using it

- **Open a project** with **Open Project…** (⌘O). You can open a sample (StudyHub or dev-skill, with labelled demo data), a local folder, a clone, or a new project.
  - For a real folder, Dev Desk reads git and GitHub directly ([ADR 0013](../../docs/adr/0013-the-app-reads-git-and-github-directly.md)): the board, branches, diffs, PR checks, `.dev/` state, `docs/survey/` and `docs/ideation/`.
- **The Shell tab.** Open a card — every card opens the same dialog ([ADR 0021](../../docs/adr/0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md)) — then click **Start shell**. The shell opens in the task's own folder ([ADR 0017](../../docs/adr/0017-a-tasks-shell-opens-in-its-own-worktree-when-asked.md)). That folder is one of three:
  - the worktree where the task's branch is already checked out;
  - a new worktree under `~/.devdesk/wt` (the location is set in Settings → Execution);
  - the project root, when the task has no branch yet.

  Nothing runs until you click.
- **The Agent tab.** **Start agent** runs Claude Code or Codex interactively in the task's folder, with the same prompt `dev run` uses ([ADR 0018](../../docs/adr/0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md)).
  - The agent comes from Settings → Agents and defaults, or from a project's override.
  - It stops at the pipeline's approval gates and asks you in its terminal.
  - A task with no branch yet gets its own detached worktree, and the pipeline creates the branch there.
- **Auto.** Turn it on in Settings → Project overrides.
  - It starts agents for the board's Queued tasks (the active GitHub milestone), in board order.
  - At most 3 run at once across all windows. You can set the limit from 1 to 6 in Settings → Execution.
  - Turning Auto on shows a token warning first: every agent spends tokens on your Claude or Codex plan, and Dev Desk can't see your usage.
- **Worktrees Dev Desk creates are kept** until you remove them with `git worktree remove <path>`.

## Development

```bash
swift test --package-path apps/desk/DeskCore   # models, the git reader, folder rules, the Auto scheduler
```

- CI (`.github/workflows/desk.yml`) runs these tests and builds the app on every change under `apps/desk/`.
- A Debug build launched with `-DevDeskAgentExecutable <absolute path>` runs that program instead of `claude` or `codex`, so a manual check never spends tokens.
- The board rules and the agent prompt mirror `scripts/dev.py`, so a change to one needs the other ([ADR 0013](../../docs/adr/0013-the-app-reads-git-and-github-directly.md), [ADR 0018](../../docs/adr/0018-dev-desk-starts-the-tasks-agent-by-hand-or-in-auto.md)).
