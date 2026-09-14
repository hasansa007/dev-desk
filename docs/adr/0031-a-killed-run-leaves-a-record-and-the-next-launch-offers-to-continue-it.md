# 0031 — A killed run leaves a record, and the next launch offers to continue it

Status:  Accepted
Date:    2026-09-14
Commit:  (this branch)  ·  `main`
Amends:  0025 (a background run belongs to the app, not the window) — its lifetime rule stands; only the record outlives the app

## Context

Everything the app knew about what was running lived in memory and nowhere else. `JobRegistry.jobs` is
an array; a terminal session is a child process tracked by `ShellSessions`, `ShellTerminalRegistry` and
`LiveShells`, none of which writes anything down. Quitting was handled — `endAllBeforeQuit` signals the
shells, `QuitGuard` asks first when something is live.

**Being killed was not.** Force-quit, a crash, a reboot: the processes die, and with them every trace
that they existed. The next launch opens on an empty Terminals screen. A `dev:survey` fan-out forty
minutes in, an agent halfway through a worktree, a run stopped and waiting for an answer — all of it
reads exactly like a machine on which nothing had ever been started. The developer cannot even find
out **what** was lost, let alone continue it.

ADR 0025 settled the lifetime question deliberately: runs are children of the app and end with it, and
the detached shape — processes surviving quit, reattached on launch — was rejected by name. That
decision is not in question here. What is in question is whether losing the *processes* has to mean
losing the *knowledge*, and it does not: those are two different things that were only ever lost
together because nothing wrote the second one down.

## Decision

**1. A live run is written down, in the project it runs in.** `RunJournal` keeps one JSON file per
record under `<projectRoot>/.devdesk/runs/`, holding what it takes to describe and continue a run:
what it was, its agent and door, when it started and when it was last seen, its session id when one
was reported, the grant and mode it was started under, its last state label and the tail of its log.
A file per record rather than one index, because the app's registry and every open window write here
at once, and a shared index is the thing that loses a run when two of them rewrite it.

**2. This does not reverse ADR 0025.** No process survives quit, nothing is reattached, nothing is
launched at startup. What survives is a **record**. The bargain 0025 struck — runs are the app's
children and die with it — is exactly as it was; a crash simply no longer takes the evidence with it.

**3. `clean` is the crash test, and the app never has to detect a crash.** A record is written unclean.
A graceful **end** deletes it — a finished run is history, and resurfacing it as "in progress" would be
a lie the user acts on. A graceful **quit** marks it clean: `LiveShells.endAllBeforeQuit` for sessions,
`QuitGuard.applicationWillTerminate` for background runs. A kill runs neither, so the record stays
unclean, and an unclean record at the next launch *means* "this was live when the app died". Nothing
samples a heartbeat and nothing guesses.

**4. Recovery is an offer, never an action.** Records for a project appear as a **Recovered** section
above the live rows in Terminals: title, what it was, when it was last seen, its last state and the
end of its log. Nothing restarts by itself — the same principle as 0025's reopening that reconnects
rather than auto-launching copies. The only automatic step is the opposite one: once the offer has
been shown, clean records are purged so the folder cannot grow forever. Unclean ones are left, because
dismissing one for the user is answering for them.

**5. Each row offers only what it can honestly do.**

| What was captured | Offer | What it actually does |
| --- | --- | --- |
| A background run with a session id | **Resume** | `JobCommand.resume` on that session, under the grant and mode the dead run held, told plainly that it was interrupted |
| A background run with no session id | **Run the door again** | A new run of that door, from the start |
| A terminal session | **Open the task** | Opens the task so a session can be started again |
| Anything | **Dismiss** | Deletes the record, and nothing else |

Handoff is never worded as restoration. The conversation an agent had in a killed terminal is in that
agent's own transcript, not in the app, and a button that implied otherwise would be the one thing
worse than the empty screen this replaces.

## Consequences

- `RunJournal` and `JournalRecord` live in DeskCore and are tested against a temporary directory —
  round trip, overwrite, ordering, sanitised filenames for ids like `job:survey:ab12cd34`, and a
  corrupt file being skipped rather than costing the user the other records.
- `JobRegistry` takes a `journalFor` **closure**, not a journal: the registry is the app's and spans
  projects, while a journal is one project's folder. Nil is then the honest answer for a sample, which
  has no folder, and for every test that is not about journalling.
- A run rewrites its record on every state change and every line it logs. The file is small and the
  write is atomic, so a record half-written when the app is killed is not possible — which is the only
  case this feature exists for.
- **`.devdesk/` is git-ignored.** The journal is per machine and per moment; it is not project history.
- **The recovery offer has not been exercised against a real crash.** The journal and the registry's
  use of it are tested; what is unverified is the screen, which was compiled but not force-quit into.
  An observation is not a test either way, and this one has not been made yet.

## Alternatives rejected

```
rejected: keep processes alive past quit and reattach — 0025 rejected it with reasons that have not
          changed: orphan reconciliation every launch, runs nothing is watching, processes alive after
          you quit. The complaint being answered here is amnesia, not mortality
rejected: one index file per project — simpler to read, and the failure mode is two windows rewriting
          it at once and losing the run that was not in the copy that landed last
rejected: auto-resume everything unclean at launch — spends tokens on work nobody asked for, in a
          repository that may have moved on, and turns a crash into a second crash's worth of runs
rejected: keep the record after a graceful end so Terminals has a history — the recovery list would
          then be mostly finished runs, and the one thing it must not do is present finished work as
          interrupted work
rejected: detect the crash instead (a heartbeat file, a pid check) — more moving parts to answer a
          question `clean` already answers exactly, and a stale pid is reused by another process
rejected: a Resume button on every row, disabled with a tooltip when there is no session — a disabled
          button still promises the feature exists; an absent one promises nothing
```
