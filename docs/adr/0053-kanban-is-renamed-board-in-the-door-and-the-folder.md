# 0053 — Kanban is renamed Board, in the door and the folder

Status:  Accepted
Date:    2026-09-20
Commit:  (this commit)

Follows [0042](0042-survey-is-renamed-findings-in-the-app-the-door-and-the-folder.md), which renamed
Survey to Findings for the same reason and set how a rename is carried out here.

## Context

`dev:kanban` was the only name in the family that came from outside it. Everything the door touches
already says **board**:

- Dev Desk's screen is the **Board** (`BoardScreen.swift`), since [0014](0014-dev-desk-replaces-dev-ui.md).
- The helper subcommand is `dev board` — it computes the very columns the door reports.
- [0011](0011-the-project-board-mirrors-it-never-decides.md) and [0008](0008-replace-the-board-add-the-opportunity-door.md)
  argue about *the board*, never about a kanban.
- The door's own description opens `The BOARD — what you are on, what is queued, what is next`.

So the door answered to one word and was called another. A reader seeing `dev board` in the helper
table and `/dev:kanban` in the command table has to learn they are the same thing, and nothing is
bought by making them.

"Kanban" also claims more than the door does. A kanban board carries WIP limits and pull signals;
this one reports columns derived from git and offers bounded writes. The narrower word is the true one.

## Decision

**1. The door is `dev:board`, and its folder is `skills/board/`.** The frontmatter `name:` changes
with it, which is what the CLI reads.

**2. Live references are rewritten; the record is not.** Every file that *instructs* — the root
`SKILL.md`, `shared/entry.md`, the sibling doors that hand off to it, `README.md`, `PROJECT_MAP.md`,
`docs/guide/`, the tests, and the Swift comments naming the door — says `board`. ADRs and
`docs/superpowers/` specs and plans keep `kanban` as written: they record what was decided at the
time, and editing them would make the history say something that never happened. 0042 did the same.

**3. `docs/arch/` is regenerated, not edited.** The three diagrams and their JSON are Archify output
pinned to real commits; hand-editing the word would break the pinning. They are stale until
`dev:arch` runs, which is a separate change.

## Consequences

- `/dev:kanban` no longer exists. There is no alias: one name per door, and a deprecated second name
  is exactly what 0042 refused to keep.
- Anything outside this repo hardcoding `kanban` — a saved prompt, a script, a shell alias — breaks
  and must be updated by hand. Nothing inside the repo dispatches on the string: `scripts/dev.py`
  resolves a door by directory, so it needed no change, and its tests passed once their fixture
  names moved.
- `dev board` (the helper) and `/dev:board` (the door) now differ only by the slash. They are the
  computation and the judgment over the same thing, so the near-collision is the point, not a cost.
