## Phase 9 — Implement

### Pre-edit — Impact Analysis
Before touching any file:
1. Re-read `PROJECT_MAP.md` to confirm your understanding of the system
2. Identify all files that will be affected (including indirect callers)
3. Check `SYSTEM_FLOW` — every change must serve the user journey
4. Verify no scope creep: is every change strictly required by the ticket?

### Editing — Surgical Protocol
- **Touch only what must be touched.** Do not reformat adjacent code, rephrase old comments, or fix style you find imperfect (`dev:comment-budget --apply` excepted, per Universal Rules).
- **Style matching.** Adhere to the code style in the file you are editing, even if you find it imperfect. Consistency > personal preference.
- **Clean your own mess.** If your change orphans a function, import, type, or parameter — remove it.
- **Execution simplicity.** If 50 lines can do the job instead of 200, write 50. Do not over-abstract.
- **No placeholders or TODOs.** Code must be production-ready and complete. Handle real errors; do not leave stubs.
- **No narration inside a body.** Running commentary on the next few lines means the name is wrong —
  fix the name. The one line *above* a function is the budget, not a violation of it. Tests carry
  the case in the name: no docstring, no AAA banners (Short Documentation).
- **Commitment to flow.** Every single line of code must serve the user journey defined in `SYSTEM_FLOW`. If a line does not, delete it.

### Task Execution
- For complex tasks (3+ files touched): use the `subagent-driven-development` skill to dispatch implementer + reviewer subagents per task
- When the user requests TDD or the task involves critical logic: follow the `test-driven-development` skill (red → green → refactor cycle)
- **Postgres / Supabase in the diff** — schema, migrations, RLS, auth, storage, edge functions: use the `supabase` skill for the mechanics and `supabase-postgres-best-practices` for any query, index or schema-shape decision. A migration is a Deep-tier change by definition, whatever the diff size — it is the one edit that can take production down without a code bug.
- Mark each `[x]` when complete
- Commit after each logical task (new commit — never amend)
- Prefer editing existing files over creating new ones
- Mirror existing patterns — do not invent new conventions

### Post-task — Self-Verification
- Does the code handle errors and edge cases? (Production-Ready rule)
- Are there automated tests for the new logic? (Self-Verification rule)
- Did I leave any orphaned symbols? (Clean Your Own Mess)
- Is every change strictly in scope? (Prevent Feature Creep)

### Completion
Print summary of changed files, any assumptions made, and flag any incomplete features for `ORPHANS & PENDING` in `PROJECT_MAP.md`.

---

