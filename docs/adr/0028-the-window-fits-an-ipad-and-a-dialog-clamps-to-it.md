# 0028 — The window fits an iPad, and a dialog clamps to it

Status:  Accepted
Date:    2026-09-13
Commit:  (this branch) · `main`
Amends:  0021 (one dialog size)

## Context

The developer asked for the minimum width to be fixed, naming iPad-class screens. Four separate
rigidities made everything under 1100 pt unusable, and each was written as if it were the only one:

- the project window's floor, `minWidth: 1100, minHeight: 720`;
- the dialog, a fixed `900 × 660` — ADR 0021's "one dialog size", taken literally;
- the launcher, a fixed `1000 × 540` in a scene with `.windowResizability(.contentSize)`, so it could
  not be resized at all;
- the sidebar, a fixed 236 pt, which a narrow window cannot spare.

Measured against real displays: an 11" iPad as a second screen is 1194 × 834 — it fits with 94 pt to
spare and no room to breathe. Sidecar on older iPads is 1024 × 768, where **the app cannot open**.
Half a MacBook screen is 756–864 pt wide, which was never in question.

The developer's own screens, asked for and answered: an 11" iPad as a display, half a MacBook
screen, and 1280 × 720-class externals.

## Decision

**1. Two floors.** The comfort floor is **920 × 620** — everything as designed. Between 920 and about
760 pt exactly one thing changes: the board's columns keep their width and scroll horizontally, which
`BoardScreen` already did. Everything else already fits.

**2. Below 1100 pt the sidebar is an icon rail** of 64 pt: symbols with their titles in tooltips, a
waiting badge as a dot on its icon, connections as dots that open Settings → Accounts. It is also a
choice at any width — **Compact Sidebar**, ⇧⌘S — and the automatic collapse wins while the window is
narrow, handing the choice back when it widens.

**3. A dialog is a maximum, not a size.** `deskDialogFrame` clamps to
`min(900, window − 40) × min(660, window − 40)`, and the sheets that set their own width clamp the
same way. **This amends ADR 0021**, whose intent — no per-card dialog sizes, one shape for every card
— is unchanged: what is fixed is the *maximum*, and a window too small for it gets a smaller dialog
rather than a clipped one.

A sheet cannot measure the window it covers, so the window measures itself once
(`GeometryReader` in `ProjectWindow`) and passes the size down as `\.deskWindowSize`.

**4. The launcher resizes**, minimum 720 × 460, and its two columns stack under each other when there
is no room for both (`ViewThatFits`). The scene's resizability becomes `.contentMinSize`.

**5. The Files edge yields first**: its 420 pt default clamps to 45% of the window, because a 420 pt
panel on a 920 pt window leaves the board a strip.

## Alternatives

```
rejected: a floor of 1024 × 700 with the sidebar left alone — the least work, but it is an exact fit
          on the developer's own iPad and still impossible on half a MacBook screen
rejected: fluid down to ~760 everywhere — the board scroll is the only sub-920 behaviour these
          screens actually need, and every other panel would gain a breakpoint nobody asked for
rejected: an iPad app — an iPad cannot spawn a PTY or run claude/codex, so that is the container
          spec's remote-host future, not a layout question. Fluid layouts are its cheap preparation
```

## Consequences

- The app opens on 1024 × 768 Sidecar, and is comfortable at 1194 × 834 and on half a MacBook screen.
- ADR 0021 is amended, not reversed: one dialog, one shape, clamped.
- Two new preferences: `desk.sidebarRail`, and the breakpoint as a metric rather than a literal.
- The rail is a second rendering of the sidebar, so a destination added to one must be added to
  neither — both read `Destination.allCases`.
