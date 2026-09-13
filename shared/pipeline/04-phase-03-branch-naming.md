## Phase 3 — Git Branch Naming

| Source | Branch name |
|---|---|
| GitHub | `gh-{N}-{slug}`: e.g. `gh-42-add-dark-mode` |
| Generic | `feature/{slug}`: e.g. `feature/dark-mode-toggle` (max 5 words, lowercase, hyphens) |

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

If the branch already exists (a resumed task, or the developer cut it), say so and move on — this
is about not pre-committing, not rejecting work in progress. **But check its base:** a branch cut
from another in-flight branch carries its commits into your PR. Mechanics and scar in `entry.md`.

---

