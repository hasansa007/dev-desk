# 0056 — Sessions' New session is a "+" after the last tab

Status:  Accepted
Date:    2026-09-26
Commit:  (this commit)

Amends [0046](0046-one-task-model-three-views-findings-keeps-its-name.md) decision 14, which took Sessions'
"+" away because the header's New session button was the same action. The rest of decision 14 stands: one
header on every tab, drawn by `ScreenHeader`.

## Decision

Sessions opens a new session from a **"+" that is the last element of the tab row**. The header's New session
button is gone, and Sessions' header now has no primary button. The "+" uses the tabs' height and hover
fill, is disabled with the refusal as its help when a shell cannot start, and opens a login shell at the
project root in front, as the button did.

Requested by the developer, 2026-09-26: *"replace current new session button with a "+" tap as last element of
the terminals tabs"*.

## Why

A tab bar's new-tab control belongs at the end of the tabs, where every browser and terminal puts it. In the
header it sat a screen width away from the row it adds to.

## Consequences

- Sessions is the one tab whose header has no primary button. Decision 14 allows that: it says *at most one*.
- The dock's `+` (ADR 0052) and this one are now the same shape for the same action.
- The empty-state starter's *Start with* menu and *Start session* button are gone too: they offered the same
  choices as the "+". The starter keeps its text and, with no sessions listed, *Go to the board*. Requested
  2026-09-26: *"remove the start session and the menu picker from the empty state screen - feels duplicated
  since the "+" is displaying that"*.
