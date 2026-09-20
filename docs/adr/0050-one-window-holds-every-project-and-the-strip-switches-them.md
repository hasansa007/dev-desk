# 0050 — One window holds every project, and the strip switches them

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Reverses one window per project — the shape Dev Desk has had since it was a `WindowGroup` keyed by
`ProjectRef` ([0012](0012-the-mac-app-lives-in-apps-desk.md), [0014](0014-dev-desk-replaces-dev-ui.md)).
ADR [0025](0025-a-background-run-belongs-to-the-app-not-the-window.md) — a background run belongs to the
app, not the window — is not reversed; this extends its reasoning from runs to projects.

## Context

A project existed only while a window was open on it. `ProjectWindow` built the project's
`ProjectWindowModel`, its `ShellTerminalRegistry`, its Auto loop and its start queue as its own `@State`,
so closing the window ended the project, and looking at a second project meant a second window with a
second copy of the chrome.

0025 had already found half of this: a run outlives the window that started it, because the run is the
app's. The other half was never taken. An agent that stops to ask a question in a project whose window is
behind another window — or closed — has no way to say so. The developer works across three repositories
at once; the operating system's window list was the only thing saying which of them needed them, and it
says nothing about what is happening inside one.

The Console × Focus prototype (`apps/desk/design/`, PR #87) answers it with a strip: one window, a column
of project badges down its left edge, each carrying what that project needs.

## Decision

**1. One window.** `Window("Dev Desk")` replaces `WindowGroup(for: ProjectRef.self)`, and the separate
`Window("Open Project")` launcher goes with it — Open project is a dialog raised over the one window, by
the strip's `+` or ⌘O.

**2. A project's life is owned by the workspace, not by a view.** `ProjectContext` holds what
`ProjectWindow` used to: the model, the sessions, the Auto loop, the queue. `Workspace` holds the
contexts, the strip's order and the selection, and is a singleton because with one window it is genuinely
app-wide — the menu bar, a sheet and snapshot mode all open a project without a view handing it down.

**3. Every project in the strip keeps running, selected or not.** Its loads, its Auto loop, its queue
drain and its session events all go on while you look at another project. `ProjectHooks` is rendered at
zero size for every open project, not only the one on screen. This is the whole point of the strip: a
badge can only tell you a run is waiting for you elsewhere if elsewhere is still running.

**4. The badge carries the state a window's absence used to hide.** An amber count means that many runs
are waiting on you in that project; a green dot means something is running there. The count wins when
both are true — a run that has stopped to ask you something is not news that the project is busy, it is
news that it is stuck on you.

**5. Each project keeps its own focus.** Destination, open task and task tab were `@SceneStorage`, which
is the *window's* memory; with every project in one window they overwrote each other, so switching
projects landed you wherever the last one had been. They are keyed by `ProjectRef` now.

**6. Sessions end when the window closes or the project leaves the strip** — the same two events that
used to be one. Quit is still handled once, by `LiveShells`.

**7. Nothing selected is Home:** what needs you across projects, with the project that needs you most
drawn widest. Equal tiles do not answer "where do I go now".

**8. A project's icon moves to the top of its rail.** The rail's `+ Open project` was redundant the
moment the strip grew a `+`, and the rail had nothing on it naming the project it belonged to.

## Rejected

- **Keep windows, add the strip to each** — then a project appears in two places and the badge has to say
  something different in each. The strip exists to be the one list.
- **Tear a project off into its own window** — worth having for two displays, and deliberately deferred:
  it can be added later to `Workspace` without moving anything, and it is not worth shipping the
  ambiguity before the strip has been used.
- **Suspend a project that is not selected** — cheapest, and it breaks decision 3 outright: the badge
  could never say a run is waiting for you somewhere else, which is the reason the strip is worth having.
- **One merged board across projects** — argued against and still rejected: milestones, labels and
  "Next up" are per-repository, and merging them invents a ranking no repository agreed to.
