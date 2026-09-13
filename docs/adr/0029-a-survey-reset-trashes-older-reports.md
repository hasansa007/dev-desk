# 0029 — A survey reset trashes older reports

Status:  Accepted
Date:    2026-09-13
Commit:  (this branch) · `main`
Amends:  0022 (Dev Desk deletes a local branch, and nothing else)

## Context

A survey run appends a report to `docs/survey/` and nothing has ever taken one away. A repository
surveyed weekly accumulates every finding it has ever had; the screen's run picker keeps the newest
one in front, but the history grows without end, and findings set aside in the app
(`desk.ignoredFindings.<ref>`) are never forgotten either. The developer asked for "survey reset or
cleanup — like restarting the process".

Three different parties own what builds up, which is exactly why one button could not mean all of it:

| What | Lives in | Owner |
| --- | --- | --- |
| Ignored findings | `UserDefaults`, per project | the app |
| Selected run, filters, ignored-view | the window | the window |
| Reports | `docs/survey/*.md` | the repository, written by `dev:survey` |

ADR 0022 says Dev Desk deletes a local branch **and nothing else**. ADR 0027 already moved a
`docs/backlog/` file to the Trash — but the app *wrote* that file. A survey report is written by a
door, so removing one is new.

## Decision

**1. Reset is three separately asked-for things**, each a line with its own count: bring back ignored
findings, reset the screen, move older reports to the Trash. Nothing is cleared because something
else was.

**2. The newest report is never touched.** It is the current picture of the project; a cleanup that
takes it away is not a cleanup, it is a loss. Only `.md` files directly inside `docs/survey/` count —
a subfolder is somebody's own arrangement.

**3. Reports go to the Trash, never to deletion** — the same bargain ADR 0027 makes for
`docs/backlog/`: the app's undo is the Finder's. **This amends ADR 0022**: the app now removes a
repository file a door wrote. What 0022 protects is unchanged — nothing is destroyed, and nothing
leaves without being listed by name first.

**4. A reset can end in a new run.** "Restarting the process" means the screen ends up empty with one
obvious next step, so the sheet offers to open `dev:survey` afterwards — through the same focus sheet
the screen's own button uses, so nothing executes until it is started in Terminals.

**5. It lives in both places**: the Survey header's menu, beside the button that adds to the pile, and
Settings → Project overrides under Cleanup, which says what a reset would find before it is pressed.

## Alternatives

```
rejected: archive into docs/survey/archive/ — keeps the history in the repo, but the accumulation
          it is meant to end would simply move one folder down, still tracked, still growing
rejected: outright deletion behind a typed confirmation — the 0022 shape, but a report is evidence
          somebody paid 40 agents for; the Trash costs nothing and is recoverable
rejected: app-side only, leaving the files — the reports are most of what accumulates
rejected: clearing everything including the newest run — that is not a reset, it is amnesia
```

## Consequences

- `SurveyCleanup` in DeskCore owns the rule and is tested against a temporary repository.
- ADR 0022 keeps its meaning — the app still destroys nothing — but its literal "nothing else" is
  now "and moves a `docs/backlog/` or `docs/survey/` file to the Trash when asked".
- A cleanup is per project and never runs by itself.
