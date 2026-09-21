## Phase 10 — Pre-PR Quality Checks

Scoped to `git diff <BASE_BRANCH>...HEAD`. Every build-settings/project-file hunk in it is one the ticket needs — an experiment you forgot to revert shows up here or nowhere (2026-09-22).

### PROJECT_MAP.md Sync
Update `PROJECT_MAP.md` to reflect the current state of the project:
- `TECH_STACK` — add any new dependencies, tools, or conventions introduced
- `SYSTEM_FLOW` — update if user flows changed
- `ORPHANS & PENDING` — move any incomplete or intentionally deferred work here

### Regression Scan — the static half of Phase 11's Pass 2

Same question, read rather than run — so it is written once, in Phase 11. Apply **Phase 11 → Pass
2** statically to `git diff <BASE_BRANCH>...HEAD --name-only`, asking of each changed file *"does
anything here silently affect a caller outside this ticket's scope?"*: new code changing behaviour
for existing callers, edge cases the ticket never considered, unexpected interactions between new
and old. (Style and architecture drift belongs to Phase 13, not to this pass.)

Every suspicion becomes a **named row** in Phase 11's table, where it gets executed and evidenced.
An item you cannot turn into a runnable row is one you have not understood yet. If this pass finds
nothing, say so explicitly — "no cross-scope callers touched" — because that is a claim Phase 11
can falsify, and "I looked and it was fine" is not.

> Platform-specific additions (UI previews, localization audit, release notes) are in the platform pipeline file.

---

