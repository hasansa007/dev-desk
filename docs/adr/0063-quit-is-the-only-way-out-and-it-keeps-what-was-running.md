# 0063 — Quit is the only way out, it asks, and it keeps what was running to resume

Status:  Accepted
Date:    2026-10-01
Commit:  (this commit)

Amends [ADR 0031](0031-a-killed-run-leaves-a-record-and-the-next-launch-offers-to-continue-it.md) decision 3 — "a graceful quit marks it clean".
Amends [ADR 0050](0050-one-window-holds-every-project-and-the-strip-switches-them.md) — ⌘W closing the window.

## Context

Since 0050 there is one window, so ⌘W — and the window's close button — quit the app. Nothing asked:
`QuitGuard` only spoke for ⌘Q, and only when something was live. A stray ⌘W ended every session.

And a quit, asked or not, threw the sessions away. 0031 marked every live record clean at quit, so the
next launch offered back only what a crash had killed. Quitting on purpose lost more than being killed.

> Stated by the developer, 2026-10-01: *"cmd+w closes the app, don't allow that, it should be cmd+q with
> confirmation dialog and on quit need to keep all sessions current status so we can resume once back again"*.

## Decision

1. **No ⌘W.** File › Close is removed (`CommandGroup(replacing: .saveItem) {}`). ⇧⌘W still closes a project.
2. **The close button is a quit.** It goes through `applicationShouldTerminate`, so it asks like ⌘Q.
3. **⌘Q always asks** while "Ask before quitting" is on (the default), with or without live work. Cancel is
   the default button only while something is live. A logout, restart or shutdown is not asked about.
4. **A quit keeps the records.** Instead of `markClean`, quit calls `markSavedAtQuit`: the record stays
   unclean — so `recover()` offers it — and gains `savedAtQuit: true` and a fresh `lastSeenAt`. The
   offers are 0031's own (Resume for a run with a session id, the CLI's resume for an agent session, a
   shell in the worktree otherwise); only the Recovered heading's wording changes.

0025 stands: no process outlives quit. What an agent was mid-way through stops; the conversation is
continued by the CLI's own resume, as 0031 already does after a crash.

## Alternatives rejected

```
rejected: close button hides the window and the app keeps running — the sessions would survive, but the
          window's views own the terminals, and a hidden app holding live agents is 0025's rejected shape
rejected: a separate "saved" list beside Recovered — the same record and the same offers; two lists would
          differ only in wording
rejected: auto-resume everything saved at quit on launch — 0031's reason holds: tokens spent on work nobody
          asked for, in a repository that may have moved on
```
