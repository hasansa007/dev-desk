# 0052 — The bottom edge is a dock that holds several terminals

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Stretches [0021](0021-a-card-opens-one-dialog-and-the-panels-are-the-windows-edges.md) decision 6 and
qualifies [0026](0026-a-task-has-one-session-and-terminals-is-where-it-lives.md). Neither is withdrawn.

## Context

0021 decision 6 reads:

> **6. Files and Runs are edges of the window, and nothing floats.** Runs along the bottom of the work it
> came from, Files down the right of everything, arranged the way Xcode arranges the same two things.

That edge was one panel showing one run. In use the developer has three or four sessions going at once —
an agent on a task, a door run, a plain shell — and the panel showed whichever was selected, so watching
two meant switching between them or leaving the work for the Sessions tab.

0026 says a task has one session and **Terminals is where it lives**. A second host for a live terminal
is what makes that sentence false.

## Decision

**1. The bottom edge is a dock, not a panel.** It holds up to four live sessions side by side, each with
its own header and its own ✕ — which hides the tile and never stops the session. The edge is still an
edge: it is still the bottom of the work it came from, still resizable, still not floating.

**2. `+` offers New session, or Resume.** Resume is offered only when there is something honest to
resume: a session recovered after an unexpected close (ADR 0031) or a task paused in In progress with a
branch and nothing live. A recovered agent session resumes through its own CLI's command
(`codex resume --last`, `claude --continue`), never by pretending a fresh shell is the old one.

**3. The dock is scoped to the current project**, and its open state and height are stored per
`ProjectRef` — with one window holding every project (ADR 0050), a global dock state would be one
project's dock imposed on the next.

**4. There is no dock on the Sessions tab, and that is a correctness rule, not tidiness.** Sessions is
the full-size view of the same sessions. A terminal is one `NSView` in one hierarchy: showing the same
session in a dock tile and in the Sessions tab at once does not mean two views of it, it means moving it.
Hiding the dock there is what keeps 0026's "one host at a time" true.

## Consequences

- **0026 now reads "one host at a time", not "one host".** Terminals is still where a session lives; the
  dock borrows it while you are on another tab.
- **A cap of four tiles.** A fifth start pushes the oldest out of the tiles — not out of the session list,
  which is still complete in the bar and in Sessions.
- **`DockResume` duplicates the resolution logic in `TerminalsScreen.resumeAction`.** Recorded rather than
  fixed: the two render differently and the screen's version mutates its own tab selection. `DockResume`
  is the natural home if it is ever shared.

## Rejected

- **A dock across every project at once** — then `+` must first ask which project it is starting in, and
  the bar's session list stops being answerable at a glance. Parked with the strip's other cross-project
  ideas (ADR 0050).
- **Tabs in one panel instead of tiles side by side** — that is what the panel already was. Switching
  between two running agents was the problem, not the mechanism.
- **Keeping the dock on Sessions and rendering the terminal twice** — not possible, see decision 4.
