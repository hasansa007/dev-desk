# 0026 — A task has one session, and Terminals is where it lives

Status:  Accepted
Date:    2026-09-13
Commit:  (this branch)  ·  `refactor/desk-one-session-and-terminals`
Amends:  0017 (a task's shell), 0018 (the task's agent), 0021 (the dialog's tabs, the panels as edges)

## Context

The developer asked, after a day of using the built app: *"no need for terminal and agent — still did
not get why we need both."*

They are the same machinery. `ShellTerminalRegistry`, one pty, one `LocalProcessTerminalView`; the
only difference is the argv, a login shell against that shell exec'ing `claude` or `codex` with the
pipeline's prompt. The split is historical: ADR 0017 gave a task a shell, and ADR 0018 added the
agent **beside** it rather than **through** it.

The split has been paying negative rent all week. Two registries keyed by the same task id is why
`activity(of:)` needs a precedence rule at all, why the Runs panel had to be taught to ask three
separate questions (#61), why Stop has to reach into three places, and why an ended agent shows
*"Agent ended (status 129). Start again"* — a dead end that a terminal does not have, because a
terminal that finishes leaves you at a prompt.

The same day produced the other half of this. A run's terminal moved into a dialog because a 300 pt
strip could not hold one; the dialog then had to stop scrolling because `SheetChrome`'s `ScrollView`
was eating the wheel and the arrow keys a terminal needs. Every one of those steps moved the session
away from the task page.

## Decision

**1. A task has one session.** One `ShellSessions`, one `ShellTerminalRegistry`. `SessionPurpose`
moves from the registry to the session: it is recorded at `start`, because it decides how the folder
is materialised — an agent may take a detached worktree for a task with no branch, and a shell may
not. Starting the agent on a task that already has a live shell types into that session rather than
opening a second one.

**2. Agent or shell is a property, not a place.** The board's badge still distinguishes them, because
the app knows what it launched; nothing else needs to.

**3. Terminals is a destination**, and the **only** host of a live terminal — one, two or four side
by side, which is the app's own premise (Auto runs up to three agents, ADR 0018) and the one thing
an edge and a modal both cannot do.

**4. The Runs panel stays the glance**: what is live, its state, Stop. Its Open goes to Terminals.

**5. The task dialog keeps Activity, Overview, Changes and Evidence, and loses both panes.** A task
is an issue, a diff and evidence; a session is a process with a different lifetime.

## Consequences

- **Exactly one place renders a live terminal, and that is now a rule rather than an accident.** Two
  owners for one `NSView` is what made a dialog open on an empty frame while the panel kept the
  terminal; the same bug is available to any future surface that forgets.
- **Auto does not need a registry of its own to stay out of the way.** It starts where nothing is
  live, which was always the actual rule; `agentCount` counts sessions whose purpose is `.agent`.
- **A task can no longer have a shell and an agent at once.** Deliberate: nobody wants two processes
  in one worktree, and the board could not have shown both anyway — `activity(of:)` had to pick.
- **ADR 0021's "one dialog per card" holds**; what changes is what the dialog contains. Its rule that
  a dialog never changes shape is unaffected, and `SheetChrome`'s `scrolls:` escape stays for bodies
  that manage their own scrolling.
- **This deletes more than it adds** — a registry, a pane, a precedence question, and a dead end.

## Alternatives rejected

```
rejected: keep both registries and merely hide one — the confusion is conceptual, not visual, and the
          bug class (two owners, three questions, a precedence rule) survives untouched
rejected: keep the agent in the task dialog, move only the terminal — they are the same thing with a
          different argv, so splitting them across two places is arbitrary, and the one-host rule
          would need an exception on its first day
rejected: drop the Runs edge and keep only the destination — the live badges and column counts exist
          so the board can say what is running while you look at the board
rejected: a free "move to" like the reference app's — the columns are computed from git every reload
          (ADR 0011); a stored status would let the board claim Done about work git calls unfinished
```
