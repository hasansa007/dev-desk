## Output Header Format

Start every response with:

```
## Dev: <name>
Source:  <Jira | GitHub | Generic>
Type:    <Bug | Feature | Story | Task | Enhancement>
Tier:    <Light | Standard | Deep>       ← stated before starting, not after
Branch:  <branch-name>  (base: <base-branch>)
Stack:   <detected stack>
Platform pipeline: <pipeline-ios | pipeline-android | pipeline-kmp | pipeline-web>
Scope:   <platforms / modules affected>
Context: <what was loaded from Phase 1>
```

---

## Universal Rules

- **Short Documentation — one line, not zero and not a paragraph.** ONE line above a function:
  what it does, plus any rule its signature cannot carry (precedence, units, ownership). ONE line
  above non-obvious logic — a workaround, a spec quirk, a perf trade-off. Out: paragraph headers,
  per-line narration inside a body, Arrange/Act/Assert banners, and `@param`/`@returns` that only
  restate the types — **unless the repo generates docs from them** (typedoc, sphinx, godoc, Dokka,
  javadoc), where they are a build artifact and stay.
- **Test names ARE the test's documentation** — a failing test prints its name, not your comment.
  One behaviour per test; if the name needs "and", split it.
- Do not add, rephrase or reformat comments and docstrings on unchanged code (Touch Only What Must Be Touched). **The one exception is `dev:comment-budget --apply`**, whose whole job is the budget and which gates every write; it covers adding a line and collapsing one, because both are otherwise banned here
- Do not add error handling for impossible cases
- Do not create helpers for one-time use
- DB migrations: always add a new version, never modify existing ones (mechanics: `supabase` skill)
- **Never `git worktree add` when the IDE opens each worktree in its own window** — it splits the session. Branch IN PLACE in the main checkout, stashing if needed. Confirm the repo's own convention before assuming `using-git-worktrees` applies.
- If unsure about a convention, read 2–3 existing examples first
- **Nothing merges past Phases 12 and 13 (non-negotiable).** Docs and ADRs land in the SAME branch; the review is clean on the final PR diff. Not for a one-line change, not when running the whole push→PR→merge sequence in one go. Both gates are defined in their own phases — this line only says they cannot be waived.
- **Pre prod ≠ prod:** Phase 14 reaches pre prod only. Promoting to production is Phase 16, needs its own developer confirmation, and never happens autonomously.
- NEVER add `Co-Authored-By` trailers to commit messages
- NEVER add "Generated with Claude Code" or any AI attribution footer to PR descriptions
- Always present git commands in copy-paste blocks
- Never guess ticket/issue content — fetch or ask the user to paste
- **Discussion before building is Phase 5's gate, and it is not rationed.** Ask as many rounds as the ambiguity actually needs — one thread at a time, plain language, explicit go-ahead. (This replaced an older "exactly ONE round of clarifying questions" rule, which contradicted Phase 5 outright: a budget of one question is a licence to guess the rest.)
- Keep task granularity at ~1–4 hours each
