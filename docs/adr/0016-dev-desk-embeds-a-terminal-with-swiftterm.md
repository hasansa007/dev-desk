# 0016 — Dev Desk embeds a terminal with SwiftTerm, its first dependency

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `feat/desk-embedded-shell`

## Context

The design's Agents & Terminals dock shows terminals. Until now Dev Desk had only demo transcripts
there, in the two sample projects, because the app runs no process besides `git` and `gh` (ADR 0013).
A real project's tasks had no dock at all. It was the one surface that disappeared instead of saying
why.

The developer chose an embedded shell on 2026-09-11, in preference to three other options: agent
sessions started by the app, a hand-off to Terminal.app, and keeping the dock demo-only. A usable
terminal needs a PTY and a terminal emulator. The emulator has to handle the escape sequences, cursor
addressing, the alternate screen, colour, mouse reporting and wide characters that shells, editors
and agent CLIs use.

## Decision

The `DevDesk` app target depends on **SwiftTerm**
([github.com/migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT). It is
pinned with `exactVersion: 1.20.0` in `apps/desk/project.yml`. SwiftTerm's `LocalProcessTerminalView`
runs the user's login shell in a PTY inside the task's dock.

**DeskCore stays dependency-free.** Choosing the task's folder and keeping per-window shell state
both live there, tested with `swift test`. Only the view that draws the terminal and hosts its process
imports SwiftTerm.

## Rejected

- **Writing our own emulator.** It would mean weeks of VT100/xterm work before the first usable
  prompt, and then the long tail of rendering bugs that SwiftTerm has already fixed.
- **Handing off to Terminal.app or iTerm.** That needs no dependency. But the terminal would live
  outside the task's window, one per task would not be possible, and the design's dock would stay a
  mock.
- **SwiftTerm inside DeskCore.** DeskCore's tests run with plain `swift test` and no UI. The
  dependency belongs with the only code that draws.
- **Agent sessions first.** Those need the `dev jobs`/`dev events` runner contract (container spec
  §3), which is unbuilt. Step 2 starts agents *inside* this shell instead.

## Consequences

- **The app is no longer dependency-free.** For the app target, this supersedes the "no
  dependencies" constraint in `docs/superpowers/plans/2026-09-11-dev-desk-mac-app.md`. DeskCore keeps
  that constraint.
- **The first build resolves SwiftTerm over the network**, and so does `desk.yml`'s `xcodebuild`.
  `Package.resolved` lives inside the gitignored `.xcodeproj`, so the exact pin is what makes builds
  reproducible. Bumping the version is a deliberate edit to `project.yml`.
- **SwiftTerm has one principal maintainer.** If it stalls, the pin keeps working, and replacing it
  touches only `ShellTerminalView.swift`.
- **The licence is MIT, which is compatible.** This repo has no licence of its own yet (see
  PROJECT_MAP's ORPHANS & PENDING), and a public release has to settle that regardless.
