# 0021 — A card opens one dialog, and the panels are the window's edges

Status:  Accepted, amended by [0038](0038-the-survey-is-a-triage-list-and-board-controls-live-on-their-columns.md)
Date:    2026-09-12
Commit:  (this branch)  ·  `feat/macos-app-missing-features`

## Context

The gaps epic ([#59](https://github.com/hasansa007/dev-skill/issues/59)) was designed from
screenshots, before the app had been used on a real project. Its design record kept the full-screen
task workspace and added a sheet only for cards nobody had started, so a card led to one of two
different places depending on whether it had a branch.

The developer then ran the built app against this repository on 2026-09-12 and reported what using
it was actually like. Selecting a card pushed a screen and lost the board behind it. Starting a task
opened a terminal and nothing on the board said anything was running. Findings and Ideation reported
the same kind of evidence through different screens, and a Reports destination with filters over
both satisfied neither. Insights floated over the work. Files and Runs floated too, each carrying
its own Dock and Float button, which no other Mac app asks of a panel. Decisions was a whole screen
for a question that belongs to the task that raised it. Sheets were four different sizes, so opening
one changed the window's shape. The toolbar carried a Focus/Parallel pair that named two modes
without naming what changed, and pressing either usually changed nothing.

Those reports contradict the design record. A record exists to be contradicted by use.

## Decision

**1. A card opens a dialog, and only a dialog.** Started or not, every card on the board and every
card in a parallel pane opens the same `TaskDialog` over the board — Activity, Overview, Changes,
Evidence, Shell, Agent — with Start task on one that has not begun and View run on one that has. The
board stays where it was underneath. The full-screen workspace and its parts are deleted:
`TaskWorkspaceScreen`, `TaskHeader`, `AgentsInspector`, `AgentsDock`, `UnstartedTaskSheet`.

**The dock's two panes moved into the dialog rather than dying with it.** ADR 0018 landed on `main`
while this branch was open, putting the task's agent and an Auto mode in that dock. Nothing it
decided is reversed: the task's shell and its agent each keep their own worktree, their own trust
note and their own Start, as the Shell and Agent tabs. Auto is untouched — it was mounted on the
window, not on the dock, and still starts a queued task's agent where it is turned on.

**2. Every dialog is exactly 900 × 660.** `SheetChrome` takes neither a width nor a height, so a
sheet cannot choose its own; a long body scrolls. The rule is enforced by the type, not by
agreement, because four sizes is what agreement produced.

**3. Settings is a dialog, not a destination.** It is a place you visit and leave, like every other
Mac app's Settings, so it does not compete with Board and Roadmap in the sidebar. It keeps its
position at the sidebar's bottom as the control that opens the dialog.

**4. Decisions is not a destination.** A question waiting for an answer belongs to the task that
raised it, and is answered in that task's dialog. A `desk://decision` link now routes nowhere rather
than to an empty screen; the ADR such a link names is readable in the Files panel.

**5. Insights is a destination.** Asking about the project is a place you go — a chat-history rail
on the left, the conversation down the middle, the composer along the bottom — not a panel over the
work. The floating and docked `InsightsPanel` is deleted with its state.

**6. Files and Runs are edges of the window, and nothing floats.** Runs along the bottom of the work
it came from, Files down the right of everything, arranged the way Xcode arranges the same two
things. There is no Float button, no placement to restore and nothing to drag. Three toggles sit at
the top right, one glyph per edge, the sidebar included.

**7. Survey and Ideation are two destinations, each a whole workflow.** Ask what the run should
focus on, run it, read the result on screen, approve what is worth filing, and the approved becomes
backlog tasks. They were briefly merged into one Reports destination with filters; filters over two
different questions answered neither.

**8. Side by side replaces Focus and Parallel.** One button, on the board it affects, carrying the
count of tasks it would show and — when there are not two to show — the reason in its tooltip.

## Consequences

- **One shape to learn.** A card is a dialog, a door's report is a destination, a panel is an edge.
  Nothing in the window changes size or position because of what you opened.
- **The task workspace's dock went with it.** Its open/placement/split state, its restored scene
  storage and the agent-row router that set them are removed; its two panes are the dialog's last
  two tabs.
- **ADR 0011 is untouched.** The board still mirrors git and never decides. A running task shows a
  badge from the app's own session state; it is never moved between columns by the app.
- **ADR 0014 is untouched.** Card writes are still the bounded Move and Cancel, through `gh`.
- **Approval still goes through the door.** Filing a task from an approved finding or opportunity
  calls `dev:create-issue`, not `gh issue create`, so an issue the app files is shaped the way the
  door shapes every other one.

## What this overrides

| Design record decision | What it said | What replaced it |
|---|---|---|
| 4 · An unstarted card opens a sheet | a card with a branch still opens the workspace | every card opens the dialog; there is no workspace |
| 7 · Settings sits at the bottom of the sidebar | a destination, at the bottom | a dialog, opened from the bottom |
| (navigation record, 2026-09-11) Insights floats or docks | a panel over the work | a destination |

## Alternatives rejected

```
rejected: keep the workspace for started tasks — the developer asked for a dialog after using both,
          and two front doors for one card is the thing that was wrong
rejected: let a dialog pick its own size when its content is short — this is how four sizes happened
rejected: keep Decisions, folded into the sidebar's bottom — a screen for a question that has a task
rejected: keep floating panels as an option — a second placement to restore, for a window that has
          two edges and room for both
```
