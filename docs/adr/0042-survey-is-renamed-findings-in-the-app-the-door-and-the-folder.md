# 0042 — Survey is renamed Findings, in the app, the door and the folder

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Reverses the name chosen when the door was split from `dev:ideation` on 2026-09-10; every earlier ADR keeps
the word "survey" as it was written.

## Context

The developer, 2026-09-16, on Dev Desk's empty board: *"i did not like the \"survey\" can it be discover or find
or discoveries or findings"*, then *"also the dev skill dev:findings ??"* and *"match all, App, skill and
folders"*. The sidebar names what a screen holds (Board, Roadmap, Ideation), and the screen was already
`FindingsScreen` in code, so one thing had two names.

## Decision

- **The door is `dev:findings`** (`skills/findings/`). "survey the code" stays a trigger phrase; `/dev:survey`
  is not kept as an alias.
- **Reports are written to `docs/findings/`.** `docs/survey/` is still read, and still cleared by a reset, so a
  project checked before the rename keeps its findings. A run in both folders is read from the new one.
- **Dev Desk says Findings everywhere** — sidebar, header, Run findings, Reset findings — and a run of the
  door is "a findings run". The background door id is `findings`.

## Rejected

```
rejected: Discover / Find — verbs, beside a sidebar of nouns
rejected: Issues / Tickets — collide with GitHub issues and the board's cards
rejected: Audit / Review — already dev:audit and dev:review
rejected: rename only the app label — the door and the screen would name one thing two ways
rejected: move old reports into docs/findings/ — the app would rewrite a repository it only reads
```
