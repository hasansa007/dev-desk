---
name: code-review
description: >
  Phase 13 — the AI code review gate, run against a branch's diff before it can become a PR. Fans
  out reviewers, VERIFIES each finding against the code before reporting it, adds a spec-compliance
  check that every acceptance criterion maps to real code rather than to a claim, and adds a
  security pass when the diff touches money, auth, migrations, uploads or untrusted input.
  Findings are handled by verdict, never silently dropped: CONFIRMED critical is fixed before
  anything proceeds, PLAUSIBLE is judged against the code and fixed or refuted with a reason.
  It is a GATE, not a report — a diff that has not passed here does not reach Phase 14.
  Trigger when the user says "review this branch", "code review", "review the diff", "run the
  review gate", "is this ready for a PR", or after `dev:docs` clears Phase 12.
allowed-tools: [git, gh, rg, grep, Read, Agent]
---

# code-review — Phase 13, the gate before a PR exists

A **phase door**, like `dev:verify` (11) and `dev:docs` (12). It takes a durable artifact — a branch
whose diff is finished — and returns a verdict, not an opinion.

**Chaining:** `dev:verify` → `dev:docs` → **here** → `dev:pre-prod`. Phase 12 chains into this one
automatically because both read the same diff. **This one never chains into Phase 14** — opening a
PR is a decision, and `shared/entry.md` is explicit that nothing chains into a merge.

## Phase 0 — Prefer the engine, fall back to prose

If the `code-review` skill is installed, use it as the engine — it fans out reviewers and
adversarially verifies findings, which is exactly what this gate needs and what a single
self-review pass cannot give you:

```
/code-review        # against git diff <BASE_BRANCH>...HEAD
```

**If it is absent, do the passes below by hand** and say that you did. A self-review is weaker than
a verified fan-out; it is not nothing, and pretending the gate ran when it did not is worse than
either.

This door owns the **protocol** — scope, the extra passes, verdict handling, what re-runs
afterwards. The engine owns the fan-out.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| (nothing) | the current branch against its resolved base | this |
| A branch name | that branch | current |
| `--security` | force the security pass regardless of tier | on trigger only |
| `--quick` | correctness only — skip spec-compliance and security | all passes |

## Phase 2 — Resolve the repo and the diff

Read `~/.claude/skills/dev/shared/entry.md` — **the absolute path, because this skill runs inside
somebody else's repo.** It resolves the repo and, critically, the **base branch**.

```bash
git diff <BASE_BRANCH>...HEAD --stat
```

**Three dots, not two.** `A..B` shows what changed between two tips; `A...B` shows what *this
branch added* since it diverged. Reviewing the wrong one either hides your own commits or reports
everyone else's as yours.

**An empty diff is a finding, not a pass.** Say so and stop — a gate that returns clean on nothing
is indistinguishable from one that returns clean on working code.

## Phase 3 — Correctness pass

The engine's job: fan out reviewers over the diff, and **verify each finding against the code**
before it is reported. A finding nobody checked is a guess with a line number on it.

Scope is the diff, not the repo. A pre-existing problem the branch did not touch is worth a
sentence, never a blocking finding — this gate exists to decide whether *this change* can ship.

## Phase 4 — Spec-compliance pass

**Skipped under `--quick`.** Re-read the ticket or issue and confirm **each acceptance criterion
maps to actual code in the diff** — not to an implementer's claim that it does.

This is the pass that catches work which is correct and not what was asked for. The engine cannot
do it, because it reviews the diff and has never read the ticket.

| Criterion | Where it lives in the diff | Verdict |
|---|---|---|
| `<from the issue>` | `file:line`, or **NOT FOUND** | met · partial · missing |

**A criterion you cannot point at a line for is not met**, however plausible the code looks.

## Phase 5 — Security pass (conditional)

**Runs when the diff touches money, auth or entitlements, migrations, file upload or storage, or
anything that accepts untrusted input** — and whenever `--security` is passed. This is Deep tier's
addition, and the trigger is the *diff*, not the declared tier: a Light-tier typo fix that edits an
auth redirect gets the pass.

Run `security-review` against the same diff when it is available.

**Correctness review is not a security review.** It optimises for "does this do what it says"; a
security pass reads the same lines asking "what can an attacker make this do". The same reviewer
asked both questions at once reliably answers only the first.

## Phase 6 — Handle findings by verdict

Nothing is silently dropped. Every finding gets one of these, in writing:

| Verdict | Action |
|---|---|
| **CONFIRMED** critical / important | **fix before anything proceeds** |
| **PLAUSIBLE** | judge it against the actual code — fix it, or **refute it with a one-line reason** |
| Minor / style | record for later; `/simplify` is available for quality-only cleanups |

**Refuting is a real outcome and must be written down.** A reviewer told to find problems will
sometimes find one that is not there; a refutation with a reason is auditable, and a silent drop is
indistinguishable from having missed it.

## Phase 7 — Re-verify what the fixes touched

**If review fixes changed logic, re-run the affected `dev:verify` rows** — agent-run, as in Phase 11.
The evidence attached to those rows was produced against code that no longer exists.

**If the fixes were cosmetic** — comments, imports, formatting — say so and skip re-verification.
Re-running a whole checklist for a renamed variable is the ceremony that gets gates skipped.

## Phase 8 — Report, then ask

```
## REVIEW — <repo> · <branch> · <n> files, +<a> −<d>

engine        <the code-review skill | by hand, and why>
correctness   <n> confirmed · <n> plausible · <n> refuted
spec          <n>/<n> criteria met      <or: no ticket — say so>
security      <run | not triggered — and what would have triggered it>

CONFIRMED (n)   ← fixed before proceeding
- <finding> · <file:line> · <the fix>

PLAUSIBLE (n)   ← judged
- <finding> · fixed | refuted: <reason>

re-verified   <rows re-run, or: cosmetic only>
```

Then ask — **never chain**:

> "Review clean, verification evidence attached. Next is Phase 14 (`dev:pre-prod`), which pushes and
> opens the PR. Go?"

## Never

- **Never chain into Phase 14.** Opening a PR is a decision; `shared/entry.md` forbids chaining into
  a merge or a promotion.
- **Never report a clean gate on an empty diff** (Phase 2).
- **Never drop a finding silently** — refute it in writing or fix it (Phase 6).
- **Never accept an acceptance criterion on a claim** — point at a line or mark it missing.
- **Never let a correctness pass stand in for a security pass** when the diff triggers one.
- **Never block on a pre-existing problem the branch did not touch.** Say it in a sentence.
- **Never claim the engine ran when it did not.** Say "by hand" and mean it.
- **Never review a repo other than the resolved one.**

## Known limits

| | |
|---|---|
| Scope is the diff | A design flaw spread across untouched files is out of scope here — that is `dev:survey` |
| Spec compliance needs a ticket | With none, say so; do not invent criteria to check against |
| The engine is optional | Without it this is a self-review, which is weaker. The report says which ran |
| It reads; it does not run the app | Runtime behaviour is `dev:verify`'s evidence, and this gate assumes those rows already passed |

## Scar tissue

**2026-09-10 — Phase 13 was the one phase with no door.** Phases 11, 12 and 14 each had one
(`dev:verify`, `dev:docs`, `dev:pre-prod`); 13 was ~18 lines in `shared/pipeline.md` that said *run
`/code-review`*. The family's own architecture diagram carried the observation as a card: *"Phase 13
is /code-review — 20 lines that say run it."*

That gap had a cost beyond tidiness: the protocol around the engine — the spec-compliance pass, the
diff-triggered security pass, verdict handling, re-running Phase 11 rows — lived only inside a phase
description, so invoking the review directly skipped all of it and looked complete.

**The engine stayed.** Replacing a working fan-out with a hand-rolled one would have been a
downgrade wearing a family name. This door owns the protocol and calls the engine.

**Undated, therefore unproven:** this door has never been run. The `--quick` path, the spec-compliance
table and the re-verification trigger are designed rather than observed.
