# Dev Pipeline — Shared Phases

## Guiding Principles

Derived from three operating protocols, plus rules added since. These apply across every phase.

| Principle | Source | Rule |
|---|---|---|
| **Memory Establishment** | Planning Protocol | Maintain `PROJECT_MAP.md` with `TECH_STACK`, `SYSTEM_FLOW`, and `ORPHANS & PENDING`. Read it before acting; update it after. |
| **Simplicity First** | Planning Protocol | Propose the simplest solution. Reject unnecessary complexity. 50 lines > 200 lines. |
| **Short Documentation** | Golden Rule | One line, **not zero and not a paragraph**. Delete a comment that restates the code or the types; keep one carrying what the signature cannot — precedence, units, a spec quirk. `@param`/`@returns` stay where the repo generates docs from them. |
| **Stop on Ambiguity** | Planning Protocol | If requirements are unclear, do not choose a path silently — stop and ask. |
| **Prevent Feature Creep** | Planning Protocol | Stick strictly to the requested scope. No additional features. |
| **Time Awareness** | Planning Protocol | Specify year+month. Search for latest stable versions before deciding. |
| **Goal-Oriented Execution** | Execution Engine | Define success criteria before writing code, and **confirm them after**. Know what "done" looks like. |
| **Production-Ready Code** | Execution Engine | No `// TODO`, no placeholders, no stubs. Code must be complete and handle errors. |
| **Self-Verification** | Execution Engine | Write automated tests. Do not leave a mess. Ensure no regressions. |
| **Live Synchronization** | Execution Engine | Dynamically update `PROJECT_MAP.md`. Move incomplete features to `ORPHANS & PENDING`. |
| **Commitment to Flow** | Execution Engine | Every line of code must serve the user journey defined in `SYSTEM_FLOW`. If a line does not, delete it. |
| **Surgical Editing** | Surgical Editing Protocol | Touch only what must be touched. Do not reformat adjacent code, rephrase old comments, or fix style you find imperfect — `dev:comment-budget --apply` excepted, per Universal Rules. |
| **Style Matching** | Surgical Editing Protocol | Adhere to current code style, even if you find it imperfect. |
| **Clean Your Own Mess** | Surgical Editing Protocol | If your edit orphans a function, import, type, or parameter — remove it. |
| **Impact Analysis** | Surgical Editing Protocol | Read `PROJECT_MAP.md`. Accurately identify all affected files before editing. |
| **Architectural Integrity** | Surgical Editing Protocol | DRY. Reuse shared/core components. Add logging where behavior is non-trivial. |

---

## Right-Size the Process (read first)

The deep phases are for work that earns them. Triage every task into a tier before you start
**building**, and say which tier you picked.

**Reading the affected file first is part of triage, not a violation of it.** You cannot tell an
auth gate from a typo without opening it, and the tier turns on exactly that. A cheap look — read
the file, count the referrers — comes before the tier; the investigation proper is still Phase 4.
Observed 2026-08-04: a "rename one file" task was Deep the moment the file turned out to be the
app-wide auth redirect.

| Tier | When | Process |
|---|---|---|
| **Light** (default) | Small diff, low blast radius, no money/security/migration | Existing test suite + a quick self-review of the diff. NO subagent reviews, NO browser-automation pass, no checklist ceremony. Phase 4 = only as much investigation as the bug demands. |
| **Standard** | Multi-file features, user-visible flows | Tests + run the ONE most valuable live check (the bug repro or the new flow), not the full matrix. Self-review; subagent review only if something feels off. |
| **Deep** | Money paths, auth/security, migrations, wide refactors, novel-design features — or the developer asks | Maximum **evidence and rigor**: the full evidence ladder, an agent-run checklist, verified AI review, and a security pass. The Phase 2 explorers stay **conditional**. Phase 6 is **required for every Deep feature** (see Phase 6); Deep work that is not a feature and has one obvious shape (a fix, a migration, a rename) skips both. Beyond that, Deep buys care, not agents. |

When in doubt between two tiers, pick the lighter one — the developer can always say "go deeper". A slow pipeline that gets skipped protects nothing.

**The tier must land in an artifact, not just in chat.** A tier stated once and then scrolled away
is not something anyone can hold you to — the same reason Phase 12's output is a required PR
section rather than a claim. So it goes in **two** places, every run:

- the **response header** (`dev`), or its one-line equivalent (`dev-*` siblings)
- the **PR body**, in the `## PIPELINE` section (Phase 14) — next to what was actually run

Without it, a reader cannot tell whether a thin verification section means *low risk* or
*skipped work*.

**Deep tier declares its cost BEFORE spending it.** Deep spawns 2–3 explorer agents (Phase 2),
2–3 architect agents (Phase 6) and a review fan-out (Phase 13) — real time, real money. Say what it
will cost and get a word first:

> "Deep tier: ~3 explorers + ~3 architects + the review fan-out. Go, or lighter?"

Never open a fan-out on the developer's behalf and report the bill afterwards. If they say lighter,
they are right, and the task is Standard from then on — the tier is a proposal, not a verdict.

**One pre-approval counts as the word:** a door started with `--plan=decide --max-agents=<n>` (Dev Desk's
run sheet, ADR 0043) was approved up to that limit before it started. It declares the fan-out in its
report instead of asking, and refuses — spending nothing — when the plan exceeds the limit.

**Use the developer as a fast collaborator:** when a blocker is their state (debugger, session, dashboard) or a 30-second human action beats minutes of automation, ask for it immediately and specifically — one sentence, what + why.

---

## Run Mode — automatic, always. Never ask.

**Do not ask how the run should proceed.** There is one mode: run straight through. Each phase
reports what it did and what it produced, then the next one starts — no *"shall I continue?"*,
not once, not per phase.

The question used to be asked once per run and it was a tax that bought nothing: the phases that
genuinely need the developer are enumerated below and they stop on their own, so the ask only ever
delayed work the developer had already approved. Observed 2026-08-04: a mode ask and a Phase 5 ask
arrived back to back before a single file changed.

### Four gates stop anyway

These are **decisions, not steps**, and running automatically never covers a decision:

| Phase | Why it cannot be automatic |
|---|---|
| **5 — Discuss Before Building** | the go-ahead is the developer's by definition; nothing is consent to build |
| **6 — Architecture Alternatives** | the approaches genuinely differ — they pick, you recommend |
| **14 — merge to pre prod** | the prod decision, made once against the evidence |
| **16 — promotion to prod** | never autonomous |

**Automatic means "do not ask between mechanical steps." It never means unattended.** The ceremony
is skipped, not the judgment.

### Rules

- **Automatic still reports.** Each phase says what it did and produced — it just does not stop.
  Silence is not speed.
- **A blocker outranks it.** Ambiguity, a failed gate, a destructive step or a missing decision
  stops the run exactly as it always did. Automatic suppresses *"shall I continue?"*, never
  *"this needs you."*
- **Stepping is available on request, never by default.** "Slow down" / "ask me between phases"
  is honoured for the rest of the run — confirm in one line and carry on. Do not offer it.
- **Never end a run silently.** Whatever phase you stop at — the last one, a gate, or a blocker —
  name the next phase and ask whether to continue. The full rule, which also governs a run that
  STARTED mid-pipeline, is in `entry.md` → *Never end silently.*

---

