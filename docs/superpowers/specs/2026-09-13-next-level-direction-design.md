# Dev Desk: the next level — design record

**Date:** 2026-09-13

**Status:** discussed and agreed; nothing here is built. Recorded before implementation, at the
developer's request.

**Related:** [container](2026-09-11-container-design.md) ·
[task continuity](2026-09-11-app-cli-task-continuity-design.md) ·
[the gaps epic](2026-09-12-desk-missing-features-design.md) ·
[ADR 0011](../../adr/0011-the-project-board-mirrors-it-never-decides.md) ·
[ADR 0013](../../adr/0013-the-app-reads-git-and-github-directly.md) ·
[ADR 0022](../../adr/0022-dev-desk-deletes-a-local-branch-and-nothing-else.md) ·
[ADR 0025](../../adr/0025-a-background-run-belongs-to-the-app-not-the-window.md) ·
[ADR 0026](../../adr/0026-a-task-has-one-session-and-terminals-is-where-it-lives.md)

## What was asked

The developer asked what would take the app to the next level, and to settle the direction in
discussion before any implementation. Six findings were walked through; two were dropped or
deferred, and four became the decisions below.

The starting fact, from the system model's "not built yet" list: the app starts agents only as
terminal processes, so a PTY session that is working, one waiting at a pipeline gate, and one that
ended all look the same — bytes in a terminal. Background jobs (ADR 0025) already do better: a
`JobStream` knows *asking*, and `JobPane` answers from the app. The gap is the PTY half.

## Decisions

### 1. Events are a sidecar the doors write, never a mode the app switches on

The `dev` CLI and the hooks — which already run inside every door — append events to
`.dev/events/<branch>.jsonl`: *phase reached*, *waiting at gate*, *run ended*. The app tails the
file, the same way it already reads `.dev/<branch>.json`. The PTY stays the only transport
(ADR 0026); nothing about how a session starts, runs or stops changes.

The first event built is **waiting at gate**, because it is the state that matters most: it feeds
the card badge, the Terminals row, and a notification. Everything else follows behind it.

**Truth rank.** The events file is layer-2 memory, beside `.dev/<branch>.json`: when events
disagree with git or with a live PTY, events lose. A project with no events file looks exactly like
today, so nothing needs a toggle — features light up where events exist.

```
rejected: a Settings toggle for "runner mode" — the toggle does not reduce the build cost, and it
          doubles the behaviours every later feature must define
rejected: the full runner of container spec §3 first — the sidecar is buildable in slices and may
          make most of it unnecessary; the spec stays the later option, not the first step
rejected: the app parsing PTY bytes for state — a terminal is bytes, and every door's wording change
          would break the parser
```

Cost to change later: low. Only the CLI and hooks know how events are written; only one reader
knows how they are read.

### 2. Insights, for a real project, asks — it does not analyze

Insights becomes an ask surface: a question box and a few starter prompts — *map the architecture*,
*what is unclear here*, *where should this go next*. A tap kicks a door run, exactly the pattern
Survey and Ideation already use: ask focus → run in a terminal → the artifact lands in the repo →
the screen renders it. An architecture question produces an evidence-pinned diagram under
`docs/arch/`; a strategy or clarification question produces a report.

The app never analyzes anything itself. It asks, the doors answer, the repository remembers —
ADR 0013's boundary, unchanged. This also converges Insights, Survey and Ideation on one pattern:
a question, a run, a rendered artifact.

Beside it, one free win: a **project-level session in Terminals** — a session whose folder is the
project root — so an open-ended conversation about the whole project has a place today, with zero
new architecture.

```
rejected: a native chat panel — chat needs session state the PTY cannot give; it is the payoff of
          decision 1, later, not a starting point
rejected: the app rendering live analysis from the repo — that makes the app an analyzer, which
          every ADR so far has refused
rejected: Insights as a read-only report viewer — reports without the ask are Survey again
```

### 3. A Done task offers to remove its worktree

The app creates worktrees and never closes the loop. When a task's PR has merged, its card offers
**Remove worktree** — manual, never automatic, with a typed confirmation only when uncommitted
changes would be lost, exactly the shape ADR 0022 gave branch deletion.

```
rejected: automatic removal after merge — deleting a folder an agent worked in, unasked, is exactly
          what this app has been right to refuse
```

### 4. Notarization waits for the open-source release

The app is personal today; open-sourcing is planned. Ad-hoc signing stays until then. The
preparation that is cheap now is not code: a license choice and a history/secrets scan. Developer ID
and notarization are the last step before the public release, not before.

## The flows pass, same day

A walk through the built flows — UI, data, settings — followed, with before/after sketches. Each
of these was confirmed by the developer.

### 5. Notifications fire from what the app already knows

The Notifications pane's three stored toggles map one-to-one onto states `JobRegistry` already
has: *Decisions that need you* → `.asking`, *Completed work* → a clean end, *Failed runs* →
`.ended(failed:)`. Wiring `UNUserNotificationCenter` to them needs nothing from decision 1;
terminal sessions join later, when the events sidecar can report their state. Clicking a
notification focuses the project window with that row expanded. The pane's caption — *"managed
work, which Dev Desk doesn't run yet"* — was true before ADR 0025 and is corrected.

This moves ahead of everything: it is the "come back, I need you" experience, available today.

### 6. Terminals rows: the last line shows, and any ended row can leave

A collapsed row shows the last non-empty transcript line, faint, under the title — display of
bytes the app already keeps, not state inference, so decision 1's rejection of PTY parsing is
untouched. And one rule replaces three fates: **any ended row offers Remove** (a scratch
terminal's stays named Close). Ended door and task rows are no longer permanent residents.

### 7. Waiting outranks running, and tapping it opens the clarification

Running goes quiet; *needs-you* is the only loud state. The sidebar badge counts them separately
— running plain, waiting bold — and a card's badge says "Waiting for your answer". **Tapping
that badge opens the clarification itself**: for a background job, the answer box; for a PTY
session (once events name the state), the session in Terminals. The waiting state is never a
label you then go hunt for.

### 8. Settings panes say whose they are

The Project overrides pane splits into **From the repository** (read-only facts) and **Dev Desk ·
this project only** (the connection override, Auto) — its old caption denied the two Desk
preferences sitting under it. Every pane header gains its scope ("Execution — all projects").
The "Available models" section, a paragraph explaining its own absence, folds into the
capabilities note. The worktree-location field validates its path on edit instead of failing
later at session start. And `"Codex"` as the default connection collapses from three hardcoded
sites into one constant.

### 9. Refresh becomes two tiers, on the watcher decision 1 needs anyway

Today one `load()` does git (milliseconds) and `gh` (network) together, every 120 seconds.
Instead: a file watcher on `.git/refs/`, `.dev/`, `docs/backlog/` reloads the local facts
instantly; `gh` keeps the 120-second tier plus window focus; `.dev/events/` rides the same
watcher. A local commit reaches the board in about a second instead of up to two minutes. This
reverses the polling design the code embodies, so it lands with an ADR.

### 10. Every start lands where the work became visible

"Start task" dismissed the dialog and left you on the board; "Start agent" landed in Terminals
with the session selected. One rule now: **every start lands in Terminals**. Starting three
tasks in a row was the argument for staying — and Auto already does that better.

```
rejected: stay on the board and badge the card — keeps the asymmetry for a batch flow Auto owns
rejected: a toast with a link — both behaviours, one more concept
```

### 11. Auto is a toolbar chip

Auto is the app's only unattended-spending state, and it lived two levels deep in a dialog. It
becomes a toolbar chip beside the refresh ring — `Auto · 2/3` — showing slots in use, pausable
in one click. The Settings toggle and the token-warning alert stay exactly as they are.

```
rejected: a mark on the Terminals sidebar row — a mode is not a destination
rejected: Settings only — live spending state should not be two levels deep
```

### 12. At open-sourcing: the connection override moves to the repo, Auto never does

Both are per-project preferences in `UserDefaults` today — per-machine, invisible to the repo.
When the app is open-sourced, "this project prefers Claude" belongs to the project (something
like `.dev/desk.json`); **Auto stays per-machine forever, because it spends the machine owner's
tokens**. Decided by ADR when it happens; nothing moves before then.

### 13. The window scales down to iPad-class screens

Four stacked rigidities made anything under 1100 pt unusable: the window floor
(`minWidth: 1100 × 720`), the fixed 900×660 dialog, the fixed 1000×540 non-resizable launcher,
and the fixed 236 pt sidebar. An 11" iPad as a display (1194×834) fit with no margin; Sidecar at
1024×768 could not open the app; half a MacBook screen (~756–864 pt) was out of the question.

The developer's screens: an 11" iPad as a display, half a MacBook screen, and 1280×720-class
externals. So, two floors:

- **Comfort floor 920×620** — everything as designed. Below ~1100 pt the sidebar collapses to
  an icon rail (~64 pt, tooltips carry titles); the rail is also manually toggleable at any
  width, and the automatic collapse overrides an open sidebar until the window widens again.
- **Survival floor ~760 pt wide** — between 920 and 760 exactly one thing changes: the board's
  columns keep their width and scroll horizontally. Everything else already fits.

The dialog clamps instead of fixing: `min(900, window−40) × min(660, window−40)` — which amends
ADR 0021's "one dialog size" to "one dialog **maximum**, clamped to the window"; the intent (no
per-card sizes) is unchanged. The launcher window becomes resizable (min ~720), its two columns
stacking when narrow. The Files edge's width clamps to a fraction of a narrow window.

```
rejected: floor 1024×700 with a fixed sidebar — least work, but exact-fit on the developer's
          own screens, and half a MacBook stays impossible
rejected: fully fluid to ~760 everywhere — the board scroll is the only sub-920 behaviour the
          chosen screens actually need
rejected: an iPad app — an iPad cannot spawn PTYs or run claude/codex; that is the container
          spec's remote-host future, not a layout question
```

Lands with an ADR (it reverses the recorded window floor and amends 0021), in slice 1: it is
layout-only and unblocks daily use on the developer's screens.

### 14. Provider sign-in runs in a scratch terminal, and the app never touches credentials

The Accounts pane grows **Sign in…/Sign out…** per connection. Each button opens a scratch
terminal in Terminals with that CLI's own command typed in (`gh auth login`, `claude login`,
`codex login`; sign-out behind a confirm, since it breaks running work). The CLIs own the
keychain, the OAuth dance, and the token churn; the app shows identity — account, plan, version —
read from each CLI's status command at refresh time, displayed and never stored. The "GitHub is
unavailable" banner's Reconnect popover-with-instructions becomes the same Sign in… action.

The sidebar's Connections section follows, spotted from its screenshot:

- its caption — *"it doesn't sign in to them"* — becomes stale the day this ships; it changes to
  the true sentence: credentials are never stored, sign-in runs each CLI's own command in a
  terminal;
- the GitHub row stops conflating two failures: `gh` signed out gets Sign in…, **no remote** is
  not an auth state — its remedy is adding a remote, and ADR 0027's local backlog already covers
  working without one;
- Gemini reads found-but-usable while `AgentChoice` refuses it; the label becomes
  "found · not supported";
- the rows stay display-only, and a click lands on Settings → Accounts, where the actions live.

```
rejected: native OAuth in the app — the app would hold tokens, and three providers' auth churn
          becomes Dev Desk's maintenance burden
rejected: a terminal inside the Settings dialog — SheetChrome plus a terminal re-fights the
          scroll-and-keys battle ADR 0026 records
rejected: a detached mini window — a third surface for terminals breaks the one-host rule
```

### 15. Quitting with live work asks first, on by default

Quit — or closing a project window — while agents or jobs are live shows "N agents are running —
quit anyway?". It appears only when something is actually live, and a Settings toggle can turn it
off. Today `willTerminateNotification` ends them silently.

### 16. Three settings surfaces from the container-app survey

- **Worktrees inventory**: every worktree Dev Desk created, its task, its size, orphans flagged
  (task gone, branch merged), with decision 3's Remove flow. Decision 3 covers the Done card;
  this covers the leftovers already on disk.
- **Diagnostics**: a row that runs `dev doctor` in a terminal — ask-and-kick applied to health;
  the CLI already exists.
- **Updates**: a gh-release-based check, landing with the notarization slice (decision 4), not
  before.

Declined from the same survey, each crossing a recorded boundary: per-session permission modes
(the pipeline's gates own that), model/prompt/routing storage (the CLI's), a chat composer
(decision 2's rejected branch), display language and an in-app browser.

### 17. Activity renders the beats; the terminal stays one click deeper

The task dialog's Activity tab renders the event stream as a step timeline — "Phase 4 ·
implementing · 11 min ✓ / Phase 6 · architecture gate — waiting ◆ [Answer]" — with "Open the
session in Terminals" beneath it. Structured above, raw below. The pipeline's named phases give
the timeline steps other containers cannot have. Powered entirely by decision 1's events; where
no events exist, Activity stays as it is today.

### 18. One toolbar chip carries running, waiting, and Auto — absorbing decision 11

Instead of an Auto-only chip: `● 2 · ◆ 1 · Auto 2/3`, with a popover listing every live run
**across all projects** (jobs are app-level, ADR 0025) — click a row to land on it, plus Pause
Auto. One control answers "what is happening and does anything need me", from any window. This
supersedes decision 11's shape; its rejected alternatives and the untouched Settings
toggle/token warning carry over.

### 19. A selected card can start without opening its dialog

Context menu **Start**, and ⌘↩ on the selected card. The dialog stays the only detail view
(ADR 0021 intact); the common case drops from five beats to two, landing in Terminals per
decision 10.

```
rejected: a Start button on card hover — chrome on cards fights ADR 0024's one-block rule
rejected: dialog-only starts — five beats for the app's most common action
```

### 20. Insights ships four starter prompts

*Map the architecture* (the evidence-pinned diagram under `docs/arch/`), *What's unclear in this
codebase* (clarifications), *Where should this go next* (strategy), and *What's risky or rotting*
— the fourth routes to the survey door rather than duplicating its territory. Which door answers
each of the other three is fixed in slice 3.

### 21. An ended session's transcript can be saved

**Save transcript…** on an ended session row: one save panel, the session's output as plain
text. First declined, then reversed on one argument: a failed run that produced no commit leaves
zero trace once its row is gone — and decision 6 makes rows removable, so the loss gets *easier*
exactly when this record lands. The app already keeps the bytes; the feature is letting them
leave.

It is a bridge, not a pillar: once `.dev/events/` holds the meaningful beats durably, the raw
transcript matters mostly for filing CLI bugs and for feeding one agent another's failed
attempt. It ships in slice 2 with the Terminals row pass — same rows, same file, one commit.

## Defects and doc debt found on the way

- **`newTerminal()` id collision**: ids are `"term:\(count + 1)"`, so open two, close the first,
  open another → two rows named `term:2`, colliding in `ForEach` and in the session registry.
  A fix commit of its own.
- **`SurveyReportParser` drops numbered findings**: it accepts only `- `/`* ` bullets under
  recognized `## ` headings, but a real run wrote CONFIRMED as a ranked numbered list — so the
  screen showed the 7 held PLAUSIBLE items and silently dropped the 12 confirmed defects and the
  architecture drift. Fix on both sides: the parser learns numbered items and the drift
  sub-section; `skills/survey/SKILL.md` states that finding lines may be bulleted or numbered.
  (The `impact —`/`complexity —` chips on those cards are correct: ADR 0020's labels exist only
  once filed.)
- **Prose lagging ADR 0025/0027**: `SYSTEM-MODEL.md` still says the app "can't answer a door
  from its own UI" (JobPane does); `apps/desk/README.md` still describes the Shell/Agent tabs
  ADR 0026 removed; the Notifications caption, per decision 5. One sweep, before the events
  work, so the next spec builds on true prose.

## Not doing

- **Token/usage visibility.** Considered and declined by the developer. (The stats bar — turns,
  steps, TTFT — in the surveyed container app is the same feature and stays out with it.)

## Order of work

1. **Quick wins, no new architecture**: notifications from `JobRegistry` (5); the `term:` id fix;
   the survey-parser fix (both sides); the doc sweep; the settings pass (8); start-task landing
   (10); the width pass (13), with its ADR; quit-confirm (15); card-start via menu and ⌘↩ (19);
   provider sign-in/out (14); the Diagnostics row (16);
2. the events sidecar, starting with *waiting at gate* (decision 1), on the shared watcher with
   the two-tier refresh (9); waiting-outranks-running and tap-to-answer (7); the Terminals row
   pass (6) with Save transcript (21); the merged status chip (18, absorbing 11); the Activity
   timeline (17);
3. Insights as ask-and-kick with its four prompts (decisions 2, 20), plus the project-level
   session;
4. worktree cleanup on Done (decision 3) and the Worktrees inventory pane (16);
5. license and history scan, then notarization at release (decision 4); the Updates section (16)
   and the override-to-repo ADR (12) land there too.

## What this record does not decide

- the event schema beyond "JSONL, appended, per branch" — the first slice fixes it;
- which door answers each of Insights' first three prompts — fixed in slice 3;
- whether the full container-spec runner is ever still needed once events exist;
- the shape of `.dev/desk.json` — that ADR is written at open-sourcing, not before.
