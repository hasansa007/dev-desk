# Dev Pipeline — Shared Phases

## Guiding Principles

Derived from three operating protocols. These apply across every phase.

| Principle | Source | Rule |
|---|---|---|
| **Memory Establishment** | Planning Protocol | Maintain `PROJECT_MAP.md` with `TECH_STACK`, `SYSTEM_FLOW`, and `ORPHANS & PENDING`. Read it before acting; update it after. |
| **Simplicity First** | Planning Protocol | Propose the simplest solution. Reject unnecessary complexity. 50 lines > 200 lines. |
| **Stop on Ambiguity** | Planning Protocol | If requirements are unclear, do not choose a path silently — stop and ask. |
| **Prevent Feature Creep** | Planning Protocol | Stick strictly to the requested scope. No additional features. |
| **Time Awareness** | Planning Protocol | Specify year+month. Search for latest stable versions before deciding. |
| **Goal-Oriented Execution** | Execution Engine | Define success criteria before writing code. Know what "done" looks like. |
| **Production-Ready Code** | Execution Engine | No `// TODO`, no placeholders, no stubs. Code must be complete and handle errors. |
| **Self-Verification** | Execution Engine | Write automated tests. Do not leave a mess. Ensure no regressions. |
| **Live Synchronization** | Execution Engine | Dynamically update `PROJECT_MAP.md`. Move incomplete features to `ORPHANS & PENDING`. |
| **Commitment to Flow** | Execution Engine | Every line of code must serve the user journey. Refer back to `SYSTEM_FLOW`. |
| **Surgical Editing** | Surgical Editing Protocol | Touch only what must be touched. Do not reformat adjacent code or rephrase old comments. |
| **Style Matching** | Surgical Editing Protocol | Adhere to current code style, even if you find it imperfect. |
| **Clean Your Own Mess** | Surgical Editing Protocol | If your edit orphans a function, import, or type — remove it. |
| **Impact Analysis** | Surgical Editing Protocol | Read `PROJECT_MAP.md`. Accurately identify all affected files before editing. |
| **Architectural Integrity** | Surgical Editing Protocol | DRY. Reuse shared/core components. Add logging where behavior is non-trivial. |

---

## Right-Size the Process (read first)

The deep phases are for work that earns them. Triage every task into a tier BEFORE starting, and say which tier you picked:

| Tier | When | Process |
|---|---|---|
| **Light** (default) | Small diff, low blast radius, no money/security/migration | Existing test suite + a quick self-review of the diff. NO subagent reviews, NO browser-automation pass, no checklist ceremony. Phase 4 = only as much investigation as the bug demands. |
| **Standard** | Multi-file features, user-visible flows | Tests + run the ONE most valuable live check (the bug repro or the new flow), not the full matrix. Self-review; subagent review only if something feels off. |
| **Deep** | Money paths, auth/security, migrations, wide refactors, novel-design features — or the developer asks | The full pipeline: exploration fan-out (Phase 2), architecture alternatives (Phase 6), evidence ladder, agent-run checklist, verified AI review. |

When in doubt between two tiers, pick the lighter one — the developer can always say "go deeper". A slow pipeline that gets skipped protects nothing.

**The tier must land in an artifact, not just in chat.** A tier stated once and then scrolled away
is not something anyone can hold you to — the same reason Phase 12's output is a required PR
section rather than a claim. So it goes in **two** places, every run:

- the **response header** (`dev`), or its one-line equivalent (`dev-*` siblings)
- the **PR body**, on the `## VERIFICATION` line — `Tier: Standard` next to what was actually run

Without it, a reader cannot tell whether a thin verification section means *low risk* or
*skipped work*.

**Deep tier declares its cost BEFORE spending it.** Deep spawns 2–3 explorer agents (Phase 2),
2–3 architect agents (Phase 6) and a review fan-out (Phase 13) — real time, real money. Say what it
will cost and get a word first:

> "Deep tier: ~3 explorers + ~3 architects + the review fan-out. Go, or lighter?"

Never open a fan-out on the developer's behalf and report the bill afterwards. If they say lighter,
they are right — the tier is a proposal, not a verdict.

**Use the developer as a fast collaborator:** when a blocker is their state (debugger, session, dashboard) or a 30-second human action beats minutes of automation, ask for it immediately and specifically — one sentence, what + why.

---

## Phase 1 — Context Load

Runs before everything else. Reads persistent project context to skip re-discovery.

1. Check for `PROJECT_MAP.md` → load `TECH_STACK`, `SYSTEM_FLOW`, `ORPHANS & PENDING`
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions
3. Check for `specs/[feature-slug].md` → if found, resume from existing spec (skip Phase 7; for BUGS, Phase 4's reproduce-first step is never skipped — a spec is a plan, not a reproduction)
4. Report what was loaded: e.g. `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`

If a spec is found and Phase 8 or Phase 9 is the next step, skip straight there.

---

## Phase 2 — Tech Stack & Project Discovery

Always run, regardless of source:

1. **Read `PROJECT_MAP.md`** if it exists — extract `TECH_STACK` and `SYSTEM_FLOW`. If absent, create it in Phase 7.

2. **Ambiguity check:** If the requirements have any ambiguity (unclear scope, missing context, conflicting signals), stop and ask. Do not choose a path silently.

3. **Time awareness:** Note the current year and month. For any dependency, library, or tool decision, check for the latest stable version.

4. Scan root files to detect stack:
   - `package.json` → Node / React / Vue / Next.js
   - `build.gradle.kts` / `settings.gradle.kts` → Android / KMP
   - `*.xcodeproj` / `project.yml` → iOS
   - Mixed `androidApp/` + `iOSApp/` + `shared/` → KMP multi-platform
   - `Cargo.toml` → Rust
   - `pyproject.toml` / `requirements.txt` → Python
   - `go.mod` → Go

5. Identify affected platforms from the ticket/feature description.
6. Identify relevant files, models, DB tables, or modules likely touched.

**After detecting the stack, read the matching platform pipeline and apply its additions to Phases 10, 11, and 14:**

| Detected stack | Platform pipeline |
|---|---|
| `*.xcodeproj` / `Package.swift` (Swift only) | `pipeline-ios.md` |
| `build.gradle*` + Android manifest only | `pipeline-android.md` |
| `androidApp/` + `iOSApp/` + `shared/` (KMP) | `pipeline-kmp.md` |
| `package.json` → Next.js / React / Vue | `pipeline-web.md` |

### Exploration Fan-Out (conditional)

**When:** the work touches territory the context files don't cover — a new subsystem, an area
absent from `PROJECT_MAP.md`, or any Deep-tier feature. **Skip** when PROJECT_MAP + prior work
already cover the area (most Light/Standard tasks — do not fan out for a known-territory fix).

1. Launch 2–3 `feature-dev:code-explorer` agents **in parallel** (any read-only explore agent
   works if the plugin is absent), each with a DIFFERENT focus, e.g.:
   - "Find features similar to [feature] and trace their implementation end-to-end"
   - "Map the architecture and abstractions of [affected area]"
   - "Identify UI patterns, testing approaches, or extension points relevant to [feature]"
2. Ask each agent to return its findings **plus a list of 5–10 key files**.
3. **Read the flagged files yourself** before planning — the agent report is a map, not a
   substitute for the territory.
4. Fold anything durable into `PROJECT_MAP.md` (that's what makes the next task skip this step).

---

## Phase 3 — Git Branch Naming

| Source | Branch name |
|---|---|
| GitHub | `gh-{N}-{slug}`: e.g. `gh-42-add-dark-mode` |
| Generic | `feature/{slug}`: e.g. `feature/dark-mode-toggle` (max 5 words, lowercase, hyphens) |

---

## Phase 4 — Investigation

**For features:** investigation = understanding the affected area — Phase 2's Exploration Fan-Out
when it applies, otherwise targeted reads. The evidence ladder below is for **bugs**.

**For bugs — REQUIRED SUB-SKILL:** use `superpowers:systematic-debugging`. Reproduce BEFORE theorizing, and never assert a cause without a verifying probe (prefer the direct probe over inference).

Work the evidence layers in order; stop at the first layer that yields a confirmed root cause:

1. **Code audit** — trace the full path end-to-end (UI handler → API/RPC → DB), noting what each layer can and cannot cause (e.g. "this function is transactional, so ITS errors can't leave partial state").
2. **Hypothesis elimination** — list the usual suspects for the symptom class and rule them out one by one with targeted greps/reads, not intuition.
3. **Live probes** — replay the exact calls the client makes, as the real role: REST/RPC with a real token, direct DB reads, seeded fixtures. A probe that surprises you is a probe to distrust first.
4. **Live UI reproduction** — drive the real running app:
   - **Web:** Chrome DevTools MCP (`chrome-devtools` tools) — open the page, read console + network, inject `initScript` error listeners to capture what the console alone won't attribute, screenshot states. Connect to the app the developer already runs — NEVER start a competing dev server. **Kill the MCP's debug browser when the probe is over** — teardown rule + commands in Phase 11.
   - **Mobile:** build/launch via the `run` skill; drive + capture per the platform pipeline file (adb/uiautomator on Android, simctl on iOS).
5. **Environment check** — a wedged dev server, stale cache, or schema drift can BE the bug or mask it; verify the environment answers before blaming code.

Capture the confirmed reproduction as a failing test when the surface allows it — it becomes Phase 9's RED.

---

## Phase 5 — Discuss Before Building (REQUIRED)

**This gate comes before any design, plan, or code.** Phase 6 designs, Phase 7 plans, Phase 9
builds — this is where you find out whether the right problem is even being solved. It runs here,
after Phase 4, so the discussion is informed: for bugs the root cause is confirmed; for features
the affected area is understood. (Phase 3's branch already exists by now — that's fine, a branch
is cheap and reversible. An approach committed to without discussion is neither.)

Use `superpowers:brainstorming` — explore intent, requirements and shape **in plain language**,
then get an **EXPLICIT go-ahead** before producing a plan or touching code.

**Skip only for trivial changes** (typo, copy edit, dependency bump). A plan written without this
step is a guess with formatting on it.

How to run it:

- **Plain language, not file paths.** If the developer has to read a diff to follow the proposal,
  it isn't a discussion yet.
- **Step by step — one thread at a time.** Do not dump a roadmap and ask for approval of all of it.
- **Name ambiguities and contradictions explicitly, and STOP.** Never implement a silent guess;
  a wrong assumption discovered at Phase 9 costs the whole branch.
- **Propose, then wait.** "Go ahead" is a specific thing the developer says. Inferring it from
  their interest in the topic is how unrequested work gets built.

### UI discussion (conditional)

**Skip entirely for backend-only work.** When the change adds or alters anything the user sees,
settle the design here — before the plan, and long before the build:

1. **Does this pattern already exist?** Consistency is weighted heavily: parallel flows should
   reuse the same shell, the same CTA verb, and the same dialog SIZE. Find the closest existing
   surface and start from it. Actively call out and kill per-flow divergences — a second dialog
   footprint for the same job is a bug, not a variation.
2. **Reuse the design system, never invent a parallel one.** Use the `frontend-design` skill.
3. **Mock anything visually novel and get the mock APPROVED before implementing.** An approved
   mock costs minutes to change; a built screen costs hours, and by then it is defended.
4. **Say which states you are designing** — empty, loading, error, RTL/LTR — before building the
   happy path only.

---

## Phase 6 — Architecture Alternatives (conditional)

**When:** Deep-tier features, genuinely novel design decisions (new module, new data flow, several
plausible shapes), or the developer asks. **Skip** for bugs and for features with one obvious shape —
a fan-out that can only produce one answer three times is ceremony.

1. Launch 2–3 `feature-dev:code-architect` agents **in parallel** with forced-different biases:
   - **minimal change** — smallest diff, maximum reuse of what exists
   - **clean architecture** — maintainability, the abstractions you'd want in a year
   - **pragmatic balance** — speed + quality for THIS task's urgency
2. Compare the designs and form your own recommendation for this specific task (small fix vs large
   feature, urgency, blast radius).
3. Present to the developer: one-paragraph summary per approach, a trade-offs comparison, **your
   recommendation with reasoning** — then let them pick. Stop on Ambiguity applies: when the
   approaches genuinely differ, never pick silently.
4. **Write down the losers NOW.** The rejected approaches + why they lost are Phase 12's ADR
   rejected-alternatives section, and the arithmetic is only fresh once. Capture it in the spec
   (`## Rejected Alternatives`) so the ADR is a copy job, not a reconstruction.

The winning approach seeds Phase 7's plan.

---

## Phase 7 — Plan Output

> Phase 5 already settled *what* to build and, for UI work, *what it looks like*. This phase is
> only the written plan. If you arrived here without that go-ahead, go back.

Use the `writing-plans` skill to create a detailed implementation plan (seeded by Phase 6's
winning approach when that phase ran). The plan must include:

- **Exact file paths** for every file to be created or modified
- **Concrete code blocks** showing what changes (no placeholders like "add error handling" or "TBD")
- **Granular tasks** — each task should be 2–5 minutes of focused work, not hours
- **Success criteria** — what "done" looks like (from Goal-Oriented Execution)
- **PROJECT_MAP.md update** — what changes to `TECH_STACK`, `SYSTEM_FLOW`, or `ORPHANS & PENDING` are needed

```
## <TICKET / ISSUE / FEATURE>: Summary
Type | Priority | Branch | Base

## Understanding
1–2 sentence plain-language summary

## Root Cause / Approach
hypothesis (bugs) or design direction (features)

## Success Criteria
what the user sees / what tests pass / what counts as done

## File Map
which files will be created / modified and why

## Implementation Plan
numbered tasks — exact file paths — concrete changes per task

## Effort Estimate
Total estimated effort in hours

## Clarifications Needed
questions to resolve before starting

## Testing Checklist
unit + manual + regression

## PROJECT_MAP.md Impact
changes to TECH_STACK, SYSTEM_FLOW, or ORPHANS & PENDING

## PR Notes
what to call out in review
```

After producing the plan, write it to `specs/[feature-slug].md` in the repo.

After presenting the plan: ask "Any clarifications or changes before I start implementing?"

---

## Phase 8 — Task Breakdown

```
[ ] 1. <task> — <exact file path(s)> — concrete description of change
[ ] 2. <task> — <exact file path(s)> — concrete description of change
...
```

Order by dependency. Each task should be small and focused (one logical change).

---

## Phase 9 — Implement

### Pre-edit — Impact Analysis
Before touching any file:
1. Re-read `PROJECT_MAP.md` to confirm your understanding of the system
2. Identify all files that will be affected (including indirect callers)
3. Check `SYSTEM_FLOW` — every change must serve the user journey
4. Verify no scope creep: is every change strictly required by the ticket?

### Editing — Surgical Protocol
- **Touch only what must be touched.** Do not reformat adjacent code, rephrase old comments, or fix style you find imperfect.
- **Style matching.** Adhere to the code style in the file you are editing, even if you find it imperfect. Consistency > personal preference.
- **Clean your own mess.** If your change orphans a function, import, type, or parameter — remove it.
- **Execution simplicity.** If 50 lines can do the job instead of 200, write 50. Do not over-abstract.
- **No placeholders or TODOs.** Code must be production-ready and complete. Handle real errors; do not leave stubs.
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

## Phase 10 — Pre-PR Quality Checks

Scoped to `git diff <BASE_BRANCH>...HEAD`.

### PROJECT_MAP.md Sync
Update `PROJECT_MAP.md` to reflect the current state of the project:
- `TECH_STACK` — add any new dependencies, tools, or conventions introduced
- `SYSTEM_FLOW` — update if user flows changed
- `ORPHANS & PENDING` — move any incomplete or intentionally deferred work here

### Regression Verification
- Run `git diff <BASE_BRANCH>...HEAD --name-only` and for each changed file ask: "What existing behavior could this silently break?"
- Confirm no regressions exist

### Bug Scan — the cheap static pass that FEEDS Phase 11

This asks the same question Phase 11's Pass 2 asks, so do not ask it twice: **this is the reading
pass, Phase 11 is the running pass.** Read the diff and produce a list of suspected regressions;
every item on that list becomes a row in Phase 11's table, where it gets executed and evidenced.
An item you cannot turn into a runnable row is one you have not understood yet.

For each file in the diff: "Does any change here silently affect an existing caller outside this
ticket's scope?" Flag:
- New code that could silently change existing behavior for existing callers
- Inconsistencies with surrounding code style or architecture patterns
- Unhandled edge cases not covered by the ticket scope
- Unexpected interactions between new and existing code

Carry the output forward as **named rows**, not as a feeling that you checked. If this pass finds
nothing, say so explicitly — "no cross-scope callers touched" — because that is a claim Phase 11
can falsify, and "I looked and it was fine" is not.

> Platform-specific additions (UI previews, localization audit, release notes) are in the platform pipeline file.

---

## Phase 11 — Verification Gate (agent-run)

After implementation and commit, **pause** before pushing. Apply `verification-before-completion` — no claims without fresh evidence.

**The agent executes the checklist — the developer is no longer the test runner.** Build the table below, then RUN every row you can reach yourself against the live app:

- **Web:** Chrome DevTools MCP — drive the real flow (click/fill/navigate), read console + network per step, screenshot each end state. New/changed UI components get a screenshot per state variant (and per direction for RTL/LTR products).
- **Mobile:** launch via the `run` skill, then drive + capture per the platform pipeline file.
- Cover three row classes: the **bug repro** (must now pass), the **new flow** (must work end-to-end), and **existing flows** the diff could plausibly regress (must still work).
- Mark each row ✅/❌ with its evidence (screenshot, console excerpt, network status) — not a narrative claim.
- Rows the agent genuinely cannot reach (real OAuth, real payments, device-only behavior) are handed to the developer explicitly — that short list is all that remains of manual testing.

### Tear down what you started — HARD RULE

Driving the UI leaves processes behind, and they are the agent's mess to clean, not the developer's.
The DevTools MCP launches its OWN Chrome (throwaway profile under
`~/.cache/chrome-devtools-mcp/chrome-profile`) and it keeps running after the checklist: extra
windows, a stale localhost session, a second browser competing for the developer's attention and
their machine. **Kill it in the same turn the UI rows finish, before presenting the evidence.**

```bash
# Find the MCP-launched browser BY ITS PROFILE — never by app name.
ps ax -o pid,command | grep "chrome-devtools-mcp/chrome-profile" | grep -v grep
kill <pid>; sleep 2
ps ax -o pid,command | grep -c "[c]hrome-devtools-mcp/chrome-profile"    # expect 0
```

Kill ONLY what you started, and prove the boundary BEFORE killing anything:

- **Never the developer's own browser.** Match on the MCP `--user-data-dir`; a match on
  `Google Chrome` would take their tabs and their work with it.
- **Never their dev server.** They run it themselves (F5 / the run button) — it is not yours to
  stop, restart, or replace. Confirm it survived: `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
- **Same rule for everything else the phase spawned:** emulators/simulators, docker fixtures,
  tunnels, `run_in_background` shells. If you started it for a check, it does not outlive the check.
- Leave the MCP *server* alone — it relaunches a browser on demand. Only the browser dies.

Report the teardown as one line of the evidence ("debug Chrome killed, 0 left; your :3007
untouched"). An unreported leftover process is the one still running tomorrow.

Present a structured testing table:

```
## Testing Checklist — <TICKET/ISSUE>

| # | Issue | What Was Broken | Expected After Fix | How to Test | Status + Evidence |
|---|-------|-----------------|-------------------|-------------|-------------------|
```

**Pass 1 — Ticket-scoped rows:** One row per acceptance criterion or reported symptom.

**Pass 2 — Diff-scoped regression rows:** Run `git diff <BASE_BRANCH>...HEAD --name-only`. For each changed file ask: "What existing user-visible behavior could have been accidentally affected?" Add a row for every plausible regression.

**Pass 2b — Shared-surface rows: enumerate the CONSUMERS, don't reason about them.** When the diff
touches anything shared — a layout wrapper, a base CSS class, a design token, a component several
pages mount — grep for every consumer and give each one its own row. Not "the pages I edited": the
pages that *use the thing I edited*.

```bash
git diff <BASE_BRANCH>...HEAD -- '*.css' | grep -oE '^\+\.[a-z0-9-]+' | sort -u   # classes touched
grep -rn "page-shell" app --include=*.jsx                                          # then: who mounts each
```

This is not hypothetical. On 2026-07-30 a sticky-footer rule was added to `.page-shell` for the new
informational pages; that class had also wrapped home, `/join` and the course reader since the first
commit. Those three collapsed to fit-content on every screen and it reached production, because the
verification rows covered the pages in the diff and the surfaces I happened to open — HTTP 200s and a
settings dialog — never the home page behind it. **A 200 is not a layout check**, and a row per page
would have caught it in one pass. Related trap worth checking in the same sweep: a shared rule can be
*silently safe* on the page you look at for an unrelated reason (here `.pub` set `width:100%`), which
makes one green page maximally misleading.

**Pass 3 — Make each row runnable.** A row a human can't execute without guessing is not a test. Every row needs the *mechanism*, not the intent: the exact menu path, command, or state change that produces the condition ("DevTools → Network → right-click the `…/status` request → Block request URL, wait 30s"), not "simulate a failed status call".

### The checklist MUST live where the tester looks

Presenting the table in chat only is a FAILURE of this phase — the chat scrolls away and the person testing reads the PR. So:

- **Before a PR exists:** present it in chat, and carry it into the PR body's `## HOW TO TEST` section at Phase 14.
- **PR already open:** post it as a PR comment immediately (`gh pr comment <N> --body ...`).
- Lead with a copy-pasteable **Setup** block (branch checkout, install, run, the automated command + its expected counts) so the tester starts from a known state.

### Rules that make the checklist honest

- **Separate covered from uncovered.** Say which rows the automated tests already cover and which need a human. Then name the ONE row that carries the real risk — usually the happy path through code whose timing or conditions you changed — and say why the unit tests can't reach it.
- **Include a falsification row:** the check that would prove the fix WRONG if it fails (e.g. "an idle course must never trip the timeout"). A checklist that can only confirm you is not a test.
- **Declare what is NOT reachable, never invent steps for it.** If a mapped error can't be triggered through the UI (client-side guard, entitlement panel, server-only branch), say so plainly and say how you verified it instead (read the route's responses / unit test). Fabricated repro steps waste the tester's time and destroy trust in the rest of the list.
- **Paste real output, never a description of output.** Run the command, copy what it actually printed. For an observability change, show the before/after log lines — on this branch vs the base branch — because that delta IS the deliverable.

> Platform-specific build and launch steps are in the platform pipeline file.

**Verification rule:** Before claiming testing is complete, run fresh tests, read full output, and confirm the output supports your claim. Never say "should work" or "probably passes" — evidence precedes claims. State skipped/skipping tests explicitly (e.g. "20 skipped — queue tests need a real Postgres") rather than reporting a bare pass count.

Do NOT push or create a PR until the developer explicitly confirms the prod decision. What they confirm is the EVIDENCE (the executed table + screenshots + the short can't-reach list) — not a request to go test by hand. If issues surface, iterate on fixes within the current branch and re-run the affected rows.

The prod question — *is this production-worthy?* — is asked ONCE, at the end of Phase 13 (after the review is clean); Phase 11 ends by presenting the evidence, not by asking. A yes starts Phase 14, which merges to PRE PROD. The promotion to production itself is confirmed again at Phase 16: this decision approves the WORK, that one approves the RELEASE.

---

## Phase 12 — Docs & Decisions Gate (BEFORE any merge)

Code ships faster than the paper trail, and the gap is invisible until someone reads the docs and
believes them. Run this against `git diff <BASE_BRANCH>...HEAD` before the review gate:

| If the diff contains… | Then update… |
|---|---|
| a changed price, limit, cap or plan | the monetization/pricing doc — every number AND the reason it is that number |
| a decision with a rejected alternative | a new ADR in the decisions log — including the alternative and why it lost (Phase 6 ran? its losing designs go here verbatim) |
| a new/changed env var, migration or runbook step | the release/ops doc |
| a new module, flow or entry point | `PROJECT_MAP.md` (`TECH_STACK` / `SYSTEM_FLOW`) |
| work deliberately deferred | `ORPHANS & PENDING`, not a memory of it |

### The check is ACCURACY, not presence — reread what you edited

The table above asks whether the right document was *touched*. That is not the gate. **The gate is
whether every claim in the section you touched is still true**, and a partial edit passes the
touched-test while leaving the doc lying.

For each doc the diff modifies, reread the **whole paragraph or section around your edit** — not
your diff of it — and ask of each sentence: *is this still true after this branch?* Fix or delete
what is not. A doc that describes the previous design in three sentences and the new one in one is
worse than an untouched doc, because it reads as current.

Observed 2026-08-03, and it is why this subsection exists: the segmented-nav branch correctly added
ADR-73 **and** updated the PROJECT_MAP paragraph — green on every row of the table above — while
leaving three claims inside that same paragraph describing a rail the dialog no longer has. One
"rail" mention had been fixed, three had not. **A partial sweep looks identical to a complete one
from the outside**, so the pass criterion is the reread, not the edit.

Two rules that make this worth doing:

- **Write the alternatives you REJECTED, with their arithmetic.** A log that lists only what was
  chosen cannot tell a future reader why the obvious other path is wrong — so they will re-propose
  it, and you will re-argue it from memory.
- **State what is decided but NOT built.** A doc describing behaviour that does not exist yet is
  worse than silence; mark it explicitly as pending with what it needs.
- **A change that implements PART of a decision must record the remainder.** Shipping half an ADR
  silently is how a decisions log starts describing a system that does not exist — go back to that
  ADR and write which half is live and which is still intent.

Do not open the merge until this passes. Docs written after the merge get written from memory, and
memory keeps the conclusion while losing the reason.

**The output of this phase is the PR body's `## DOCS` section** — the gate lives inside an artifact
that is always produced, so it cannot be silently skipped. A PR without a `## DOCS` section is not
ready to merge. Observed failure mode this closes (2026-07-31): a feature branch with green suites
and a full verification table merged with its ADR unwritten and a stale PROJECT_MAP claim, caught
only because the developer asked — "suites green + evidence table done" is NOT this gate.

---

## Phase 13 — Code Review Gate (AI, verified findings)

Run the `code-review` skill (`/code-review`) against the branch diff (`git diff <BASE_BRANCH>...HEAD`). It fans out reviewers and adversarially VERIFIES findings before reporting — prefer it over a single self-review pass. Supplement with one **spec-compliance check**: re-read the ticket/issue and confirm each acceptance criterion maps to actual code in the diff (not implementer claims).

**Deep tier — add a security pass.** When the diff touches money, auth or entitlements, migrations,
file upload/storage, or anything that accepts untrusted input, also run `security-review` against
the same diff. `/code-review` optimises for correctness and is not a substitute for someone reading
the diff specifically looking for the exploit.

Address findings by verdict and severity:
- **CONFIRMED critical/important:** fix immediately, before proceeding
- **PLAUSIBLE:** judge against the actual code — fix or refute with a one-line reason (never silently drop)
- **Minor / style:** document for later; optionally run `/simplify` for quality-only cleanups

After review fixes, re-run the affected Phase 11 rows if any logic changed (agent-run, as above). If only cosmetic fixes (comments, imports, formatting), skip re-verification.

Then ask: "Review clean, verification evidence attached. Want me to push and create a PR?"

---

## Phase 14 — PR Creation → Review → Merge → Pre Prod

The pre prod sequence is **push → PR → review → merge → pre prod**, in that order. The review is a
**HARD GATE**: never merge or release an unreviewed diff — even when you run the whole sequence
autonomously in one go, and even for a one-line change.

**This phase ends at PRE PROD, not production.** Merging a feature branch releases it to the
pre-prod environment only. Production is Phase 16 and it has its own separate gate — do not
treat a green Phase 14 as "shipped".

**Release runbook (check first):** if the repo has a runbook (`docs/deploy-and-staging.md`
or similar), its promotion flow OVERRIDES the generic sequence — read it rather than assuming in
EITHER direction: some repos reach prod on the merge itself (the merge IS the gate), others need
a manual workflow_dispatch after merge. Get this wrong and you either reach prod by surprise or
believe you released when you didn't. Never skip the runbook's pre-prod verification steps.

**Pre-merge gates (REQUIRED, before any merge):**
0. **Phase 12 — docs & ADRs.** Prices, limits, decisions with rejected alternatives, env vars,
   migrations and deferred work are all recorded BEFORE the merge. Written afterwards they get
   written from memory, which keeps the conclusion and loses the reason.
1. After the PR exists and **before merging**, run the Phase 13 review (the `code-review`
   skill + spec-compliance check) against the full PR diff: `git diff <BASE_BRANCH>...HEAD`.
2. Fix every **Critical** and **Important** finding; re-verify (rebuild/tests) if logic changed.
3. **Do NOT merge** while any Critical/Important finding is open. "The change looks small / I
   already self-reviewed / tests pass" does **not** waive this gate.
4. Only once the review is clean (and, for interactive runs, the developer confirms) → **merge → pre prod**.

After developer confirms:

**PR body format:**
```
## SUMMARY

 - <bullet points — what was built/fixed, any safety nets added>

## VERIFICATION

 - Tier: <Light | Standard | Deep>   ← what was run is only judgeable against what was promised
 - <commands actually run + their real results, incl. skipped counts>

## DOCS                 ← Phase 12's output — REQUIRED in every PR, no exceptions
 - <docs/ADRs updated in THIS branch: ADR-NN, PROJECT_MAP section, pricing/ops doc — or>
 - none needed — checked: no price/limit change, no decision-with-alternative, no env/migration,
   no new module/flow, no deferred work, no doc made stale by this diff

## HOW TO TEST          ← the Phase 11 checklist, carried over — never left in chat only
 Setup: <branch checkout · install · run · automated command + expected counts>
 <numbered scenarios: exact mechanism → **Expect:** … → what the old behavior was>
 Not manually testable: <what, and how it was verified instead>

## JIRA / ISSUE      ← "JIRA" for Jira; "ISSUE" for GitHub; omit for Generic
https://...
```

`HOW TO TEST` may be a PR **comment** instead of a body section when the PR is already open — same content, same requirements. What is not allowed is it existing only in the chat transcript.

**Shared `gh` command:** (outer fence is 4 backticks — the PR body itself contains fenced blocks)
````bash
gh pr create \
  --title "<SOURCE_ID>: <summary>" \
  --body "$(cat <<'EOF'
## SUMMARY

 - <bullets>

## VERIFICATION

 - Tier: <Light | Standard | Deep>
 - <real command output>

## DOCS

 - <ADRs/docs updated in this branch, or "none needed — checked: ..." per Phase 12>

## HOW TO TEST

### Setup
```bash
git checkout <branch> && <install/run> && <test command>   # expect: <counts>
```

### 1. <scenario name>
<exact steps>
**Expect:** <observable result>
**Before this PR:** <old behavior>

## ISSUE
https://...
EOF
)"
````

After PR is merged, move `specs/[feature-slug].md` → `specs/archive/[feature-slug].md`.

> Platform-specific release steps are in the platform pipeline file.

---

## Phase 15 — Review Cycle (loops BACK to Phase 14)

**This is a loop, not a stage.** Human review comments arrive while the PR is still OPEN. Its
last step is `push`, never `merge` — you re-enter Phase 14's pre-merge gates and go round again
until the review is clean. It happens BEFORE pre prod, and long before Phase 16's promotion.

**Trigger:** "changes requested", "review feedback", "fix PR comments", PR URL with review, or mention of reviewer feedback.

1. **Fetch PR review comments:**
   ```bash
   gh pr view <PR_NUMBER> --comments
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments
   ```

2. **Present review feedback as structured list:**
   ```
   ## Review Changes — <TICKET/ISSUE>

   ### Comment 1 (reviewer: @username)
   File: path/to/file:42
   > quoted review comment

   **Proposed fix:** description of what to change
   ```

3. Follow the `receiving-code-review` skill protocol:
   - Restate each requirement in your own words
   - Check against actual codebase context before implementing
   - **Push back** with technical reasoning when suggestions break existing functionality, violate YAGNI, or conflict with established architecture
   - Implement one item at a time with testing

4. Ask for confirmation: "Here's the plan to address review comments. Proceed?"

5. After fixes: commit (new commit — never amend), push.

---

## Phase 16 — Prod Promotion (conditional)

**When:** the repo has a two-stage model — a pre-prod branch that feature PRs merge into, plus a
separate promotion to production. **Skip** when the repo has a single branch model, where Phase
10's merge already reached prod.

Phase 14 left the change in PRE PROD. Production is a SECOND release with its OWN gate: the
evidence that cleared Phase 11 was gathered against pre prod, and the two environments differ
precisely where the risk lives (real keys, real payment provider, real storage backend, real
data volume).

1. **Verify in pre prod first.** Run the rows only a deployed environment can answer — the ones
   Phase 11 handed over as unreachable. A green local suite is not pre-prod verification.
2. **Migrations reach prod BEFORE the promotion merge** — never after, never during. The merge
   releases code that expects the new schema; a schema arriving second is an outage. Rehearse on
   pre prod, dry-run against prod, then apply, then merge — `supabase` skill for the mechanics.
3. **Never merge while a build is running.** Two releases racing produce a deployment you cannot
   attribute and a rollback that restores the wrong thing.
4. **Read what is actually in the promotion.** It is a diff of already-reviewed commits, so it
   needs no second code review — but it does need `git log <prod>..<pre-prod> --oneline`.
   Anything you did not expect stops the promotion until you know why it is there.
5. **The promotion is the developer's call, and it is confirmed HERE, again.** Phase 11's prod
   decision approved the WORK; this one approves the RELEASE, and the two are days apart.
   Present three things — what is in the promotion, what was verified in pre prod, which
   migrations are already applied — then ask. Never promote autonomously.

**studyhub-deploy:** feature PRs target `staging`; the `staging → main` merge AUTO-DEPLOYS PROD,
so the merge IS the gate. `staging` drifts behind `main` — catch up with
`git push origin origin/main:staging`. Full flow in `docs/deploy-and-staging.md`.

---

## Output Header Format

Start every response with:

```
## Dev: <name>
Source:  <Jira | GitHub | Generic>
Type:    <Bug | Feature | Story | Task | Enhancement>
Branch:  <branch-name>  (base: <base-branch>)
Stack:   <detected stack>
Platform pipeline: <pipeline-ios | pipeline-android | pipeline-kmp | pipeline-web>
Scope:   <platforms / modules affected>
Context: <what was loaded from Phase 1>
```

---

## Universal Rules

- Do not over-engineer — minimum complexity for the current task (Simplicity First)
- Do not add comments, docstrings, or type annotations to unchanged code (Touch Only What Must Be Touched)
- Do not add error handling for impossible cases
- Do not create helpers for one-time use
- Follow the language/framework conventions already present in the codebase (Style Matching)
- DB migrations: always add a new version, never modify existing ones (mechanics: `supabase` skill)
- **Never `git worktree add` for studyhub-deploy.** The IDE opens each worktree in its own window and splits the session. Branch IN PLACE in the main checkout, stashing if needed. `using-git-worktrees` does not apply to this repo.
- If unsure about a convention, read 2–3 existing examples first
- **Docs before merge:** never merge a diff that changes a price, a limit, a decision or an env var without the doc/ADR update in the SAME branch (Phase 12).
- **Review before merge (non-negotiable):** never merge or release a diff that hasn't passed the Phase 13 review (`code-review` skill + spec check) on the final PR diff — not for a one-line change, not when running push→PR→merge→pre prod autonomously. Review → resolve CONFIRMED critical/important → then merge.
- **Pre prod ≠ prod:** Phase 14 reaches pre prod only. Promoting to production is Phase 16, needs its own developer confirmation, and never happens autonomously.
- NEVER add `Co-Authored-By` trailers to commit messages
- NEVER add "Generated with Claude Code" or any AI attribution footer to PR descriptions
- Always present git commands in copy-paste blocks
- Never guess ticket/issue content — fetch or ask the user to paste
- **Discussion before building is Phase 5's gate, and it is not rationed.** Ask as many rounds as the ambiguity actually needs — one thread at a time, plain language, explicit go-ahead. (This replaced an older "exactly ONE round of clarifying questions" rule, which contradicted Phase 5 outright: a budget of one question is a licence to guess the rest.)
- Keep task granularity at ~1–4 hours each
- Every edit must be a verifiable goal — define the success condition before and confirm it after (Goal-Oriented Execution)
- Incomplete features go in `PROJECT_MAP.md` → `ORPHANS & PENDING`, never left silently unfinished (Live Synchronization)
