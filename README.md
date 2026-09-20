# Dev Desk

**One window for every project you build with a coding agent.**

A Mac app where each project shows its board, a workspace per task, findings, the roadmap and the
decisions behind it. Each task gets a real shell and its own agent — Claude Code or Codex — running
in the task's own git worktree. Start an agent yourself, or turn on Auto for a project and it works
through the queue: at most 3 at once, after a token warning you confirm.

## Download

[**Dev Desk (.dmg)**](https://github.com/hasansa007/dev-desk/releases/latest) — macOS 14 or later.
There is no Windows or Linux build.

Open the DMG and drag **Dev Desk.app** onto the `/Applications` symlink inside it. The app is ad-hoc
signed rather than notarized, so macOS refuses it the first time with "Apple could not verify Dev
Desk is free of malware" and offers only *Done* and *Move to Trash*. Right-clicking and choosing Open
no longer gets past that on macOS 15 and later. Clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine "/Applications/Dev Desk.app"
```

It opens normally from then on. System Settings → Privacy & Security → **Open Anyway**, right after
the refusal, does the same thing.

**Or build it yourself** — needs Xcode and `xcodegen` (`brew install xcodegen`):

```bash
git clone https://github.com/hasansa007/dev-desk.git
dev-desk/apps/desk/install.sh          # --no-open to install without launching
```

That builds Release, puts it in `~/Applications`, and opens it. It is not the DerivedData bundle
Xcode builds — see [apps/desk/README.md](apps/desk/README.md) for what it does and how to work on it.

## What's in the window

| | |
| --- | --- |
| **Home** | Which project needs you, across all of them. |
| **Board** | The queue, what is in flight, what is next — read from git and GitHub directly. |
| **Task** | One card's workspace: its branch, its worktree, its shell, its agent, its diff. |
| **Findings** | Defects and architectural drift, each verified before it can be filed. |
| **Roadmap** | Themes from the repo's own evidence, written as milestones and epic parents. |
| **Decisions** | The ADRs, and which ones later decisions reversed. |

A strip down the left switches projects; each keeps its own selected task and pane layout. Opening a
project that is already open focuses its window instead of starting anything.

## The agent workflow behind it

Dev Desk drives a workflow that also runs on its own, as a skill in your agent CLI: it investigates a
problem, plans a solution, writes the code, and verifies the change before release. You approve the
decisions that matter — what to build, which approach to take, when to merge, and when to promote to
production.

```text
/dev #496
/dev fix the course list losing its scroll position
```

Bare `/dev` **orients**: it detects where the repo actually is and offers the two or three doors that
fit — resume work in flight, open the board, stock an empty tracker, or set up a fresh project. It is
read-only and never starts work.

![The dev workflow, from discovery to production](docs/assets/dev-journey.png)

*Rendered by [Archify](https://github.com/tt-a1i/archify) from `docs/arch/dev-journey.architecture.json`, where every box is pinned to a real file at a real commit. Step 1 is bare `/dev`, which detects which of four situations you are on; the numbered path that follows is the discovery route, for a codebase you do not know. `docs/arch/dev-family.html` has all 21 doors.*

**→ [Command reference](docs/guide/COMMANDS.md)** — all 21 doors, what each one takes and returns,
with worked examples.

### Installing the skill

**Claude Code — as a plugin.** The better path: a plugin carries the [hooks](hooks/README.md) as well
as the doors, and the symlink below cannot. The repo is its own marketplace, so point Claude Code at
it:

```text
/plugin marketplace add hasansa007/dev-desk
/plugin install dev@dev-desk
```

Restart Claude Code, then check a door is there — `/dev:board`, say. The root door is **`/dev:dev`**
on this path, not `/dev`: a plugin namespaces every skill under its own name. Four hooks come with
it: `branch-guard` denies a write on a protected branch, `pr-gates` checks a PR body and a push,
`teardown` blocks a stop while debug Chrome is alive, and `context-load` injects PROJECT_MAP at
session start. `branch-guard` becomes global this way, which is safe — it exempts the repo it ships
in — but every repo you work in gets the protected-branch rule.

**Codex, Antigravity, or Claude Code without the plugin:**

```bash
dev-desk/install.sh
```

Links the checkout into the skill directories that exist, skips the ones that don't, and skips Claude
Code when the plugin is installed, so the two never give you every door twice. Installed this way the
hooks do not come with it and `/dev` keeps its bare name — see [hooks/README.md](hooks/README.md).

**Installing is required, not optional.** Every path inside the family resolves through the install
root (`~/.claude/.dev-root/…`), which is what lets it run on any machine regardless of where you
cloned it. A clone that has never been installed has no root to resolve against.

### `dev` — the optional helper

A stdlib-only Python helper for the parts that are computable rather than judged: `dev doctor`,
`dev board`, `dev state`, `dev project`, `dev run`. Every door works without it; when it's there, the
doors use it instead of doing the same work by hand. `install.sh` puts it on your `PATH` when
`~/.local/bin` or `~/bin` already is. Details in the
[command reference](docs/guide/COMMANDS.md#dev--the-optional-helper).

## Learn more

- [Getting started](docs/guide/GETTING-STARTED.md) — first install, first run, and the four situations.
- [Command reference](docs/guide/COMMANDS.md) — every door, with worked examples.
- [User guide](docs/guide/GUIDE.md) — usage, compatibility, and troubleshooting.
- [Workflow](docs/guide/WORKFLOW.md) — phases, approvals, and known limitations.
- [System model](docs/guide/SYSTEM-MODEL.md) — the five layers, what Dev Desk reads and runs, and what's not built yet.
- [Contributing](docs/guide/CONTRIBUTING.md) — structure, design rules, and maintenance.

MIT. Built with [Claude Code](https://claude.com/claude-code).
