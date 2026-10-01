## Phase 3 — Git Branch Naming

| Source | Branch name |
|---|---|
| GitHub | `gh-{N}-{slug}`: e.g. `gh-42-add-dark-mode` |
| Generic | `feature/{slug}`: e.g. `feature/dark-mode-toggle` (max 5 words, lowercase, hyphens) |

**A `docs/backlog/` entry records the branch cut for it** (ADR 0045) as `branch: <name>` beside `issue:`,
its only link to git; `dev state checkpoint --local <id>` writes it, and fails on another branch's name.
Promotion adds `issue: #N` and keeps the name: renaming a branch with work on it breaks what tracks it.

### When to cut it — at the FIRST WRITE, which differs by flow

Naming is free; **creating** is what carries commitment. So:

| Flow | First write | Cut the branch |
|---|---|---|
| **Bug** | Phase 4 — the reproduction becomes a failing test | before that capture step |
| **Feature** | Phase 9 — implementation | **after Phase 5's go-ahead**, not before |

**For a feature, do not open a branch named after it before the discussion.** Phase 5 is a real
"should this exist" gate, and `feature/weekday-plan` sitting there already frames the answer as
yes — to both of you. For a bug the objection does not apply: you reproduced it, so *whether* was
never the question, only the approach.

If the branch already exists (a resumed task, or the developer cut it), say so, then **check the link**:
an existing branch proves nothing about its entry's `branch:` line. Missing → write it now — on a resume,
a mid-pipeline entry or a subagent's run alike. **And check its base:** a branch cut from another
in-flight branch carries its commits into your PR. Mechanics and scar in `entry.md`.

---

### Shared code — where to branch from, and how to land

A ticket filed by `dev:findings` carries `group:`, `needs:` and `shares:` in its `## Scope` (or its
`docs/backlog/` header). Read them before cutting, and cut from the right base:

| The ticket says | Branch from | Lands in |
|---|---|---|
| `group: G1 · n of m` | `group/<slug>`, after the ticket before it has landed there | `group/<slug>` — no separate review; the group is reviewed once |
| `needs: <id>` (ungrouped) | that ticket's branch, once its agent has finished | the base branch, after that ticket merges |
| `shares … same code, after <id>` | as `needs` | as `needs` |
| only `shares … different code`, or nothing | the base branch, now | the base branch |
| nothing — but Phase 9 fanned the ticket out | `group/<slug>`, cut here and holding the root tasks; one branch off it per slice | `group/<slug>`, then the base branch as one PR — the ticket is reviewed once |

**Before landing, dry-run the merge:** `git merge-tree --write-tree <target> HEAD`. Clean → land it.
Conflicts → rebase onto the target, re-run the Phase 10 checks, then land. A branch cut from another
ticket's branch whose ticket has since merged moves with `git rebase --onto <target> <that branch's
old tip>` — squash merges leave the old commits behind otherwise.

A group branch that is open while the base branch moves **merges** the base branch in, never rebases:
several agents branch from it, and rewriting it strands every one of them.
