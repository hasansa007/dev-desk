# 0040 — A survey files tickets in groups, and names the code they share

Status:  Accepted
Date:    2026-09-16
Commit:  (this commit)

Amends `skills/survey/SKILL.md` Phase 9 (*"two issues touching one file are conflicting, not
blocking … let whoever starts second rebase"*) and `skills/create-epic/SKILL.md` (*"files the parent
only"*).

## Context

The developer, 2026-09-16, reading CallApp's survey in Dev Desk: *"i was expecting less tickets"*,
then *"how would u prevent conflicts when multi agents will touch same file"*. CallApp's report had 26
rows for about eight fixes: three search symptoms of one matcher, a defect and a drift item on the
same line, and every shared file recorded only as `conflicts: #4, #6, #7, #10`.

That rule was written when one person started one ticket at a time, so "whoever starts second" was
known. With Auto running several agents, both start in the same second, and nothing downstream read
the conflicts line at all.

Six flows were drawn and compared with the developer (wait for merge, stack on the other agent,
group branch, parallel on different code, one agent for all). The developer chose: **related tickets
on a group branch; everything else waits for the agent whose code it shares and branches from its
work** (*"3 is good for better main merges and when we have some groups or sub groups for a feature or
epic … flow 2 for issues not grouped"*).

## Decision

- **A report entry is a ticket.** Findings that one fix resolves are folded into one entry with
  `cases:`. Sharing a file is never a fold.
- **Every entry names the code it touches** (`File › function`), its direction (`needs:`), every
  meeting with another ticket (`shares: … different code | same code, after <id>`), its `type:` (Data
  flow, Logic, UI, Architecture, Tests) and an `id:`.
- **Groups** — a `needs` chain, one flow across layers, or one drift epic — get a `group/<slug>`
  branch, an order (data → logic → UI → tests), and one review. Hotfix and security are never grouped.
- **The survey files a group's parent and its sub-issues itself.** `dev:create-epic`'s "parent only"
  rule exists because slices are imagined before Phase 5's investigation; the survey's slices are not.
- **Held cases stay held**, listed on the ticket they would join with their criticality; the developer
  decides (*"depends how critical is that"*).
- **Branching and landing** follow `shared/pipeline/04-phase-03-branch-naming.md` → *Shared code*:
  merge-tree before landing, `rebase --onto` after a squash, and a group branch merges the base branch
  in rather than rebasing.
- **Dev Desk reads it.** The survey screen opens **By group**: each group in order with its branch and
  why, then tickets on their own (with "after C3" when they wait), then held. Rows show the ticket type
  and its position; the finding dialog shows the Scope lines, and filing carries them into `## Scope`.
  A report without `## GROUPS` reads by status, as before.

## Rejected

```
rejected: one ticket per file — a bug spanning two files has no home, severities mix, "fix File.swift"
          has no outcome to verify
rejected: every shared file blocks — serialises the codebase behind its utils module
rejected: stack every dependent ticket on its parent — a review that changes the parent restacks
          the whole chain; a group branch lands them once instead
rejected: fold PLAUSIBLE cases into confirmed tickets — files what two checkers could not confirm
```
