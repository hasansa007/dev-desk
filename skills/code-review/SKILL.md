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
| `--base=<ref>` | diff against this ref instead of the resolved base — a tag, a commit, a `baseline` branch | resolved base |
| `--security` | force the security pass regardless of tier | on trigger only |
| `--quick` | correctness only — skip spec-compliance, consistency, records and security | all passes |

## Phase 2 — Resolve the repo and the diff

Read `~/.claude/.dev-root/shared/entry.md` — **the absolute path, because this skill runs inside
somebody else's repo.** It resolves the repo and, critically, the **base branch**.

```bash
git diff <BASE_BRANCH>...HEAD --stat
```

**Three dots, not two.** `A..B` shows what changed between two tips; `A...B` shows what *this
branch added* since it diverged. Reviewing the wrong one either hides your own commits or reports
everyone else's as yours.

**The repo under review is not always the one the session opened in.** When the conversation names
another repo — a path, a project, commands meant for a different history — name the target
(`owner/repo`, base, head) and confirm it before reading a line. Pass `git -C <path>` to every command
rather than trusting the working directory. Observed 2026-09-30: a review was asked for from this
family's own repo, of a take-home in another folder, against a `baseline` branch cut there minutes before.

**An empty diff is a finding, not a pass.** Say so and stop — a gate that returns clean on nothing
is indistinguishable from one that returns clean on working code.

**Uncommitted changes in the reviewed files are reported first.** `git status --short` over the diff's
paths: a file modified or deleted in the working tree means what builds locally is not what was
reviewed. The review is of the committed range; say so, and name each file.

## Phase 3 — Correctness pass

The engine's job: fan out reviewers over the diff, and **verify each finding against the code**
before it is reported. A finding nobody checked is a guess with a line number on it.

**Map every line number to the file before reporting it.** An engine working from diff output can cite
the line's position in the diff, not in the file — `Store.swift:422` in a 211-line file. Open the file,
find the code, cite its real line. A reference that does not land on the code it describes sends the
reader to the wrong place and makes every other citation suspect.

**Tests the diff adds are asked one question: what change to the code makes this fail?** Name the
mutation — *delete the line that clears the error* — and check the test would catch it. A test that
would pass either way is a finding: it looks like a regression guard and guards nothing.

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

## Phase 4b — Consistency and idiom pass

**Skipped under `--quick`.** The engine reviews the diff line by line, and neither sweep below is
visible at that range. This pass reads outside the diff to judge the diff.

**Consistency, in both directions.** List the recurring jobs the diff does: decoding images,
injecting a model, loading, empty and error states, search, formatting. For each one:

- **The diff introduces a pattern:** is it applied at every site it applies to, inside the diff and in
  the code the diff's pattern was meant to cover? A pattern carried into three screens and missed in the
  fourth is the exact defect this pass exists for. An ADR or commit message naming why the pattern
  exists ranks the missed site as important, since it still has the problem the pattern fixed.
- **The repo already has a pattern:** does the diff follow it, or add a second way of doing the same
  job? Anchor the finding at the diff's line and cite the existing site.

**Idiom.** Anything the diff hand-rolls that the platform or a dependency already ships: a custom
search bar, pull-to-refresh, empty state or observation wrapper beside the first-party one; a fetch
cache beside the data library already in use; a bespoke formatter. Also **redundant state**: a value
stored raw and re-derived on every render, or assigned twice. Each finding names what the first-party
version gives that the hand-rolled one does not.

**Ownership, for state the diff adds or moves.** For each piece of state a UI unit gains in the diff,
name its owner and ask `dev:findings` Phase 4's inventory questions: is it a copy that goes stale, data
the view could look up, one selection kept in two places, a view loading instead of reading, a
data-source decision made in the view, a display-only component that knows its source, one component's
state in a shared store, or a model holding a dependency it only uses to answer events? The questions
are that door's; this pass asks them only of what the branch added.

These findings take the same verdicts as the others (Phase 6). A missed site outside the diff is
blocking only when the diff introduced the pattern; a split that predates the branch is a sentence,
and `dev:findings` is where it gets filed.

## Phase 4c — Decision records and claims

**Skipped under `--quick`.** The engine reads code; neither check below is code.

**Does the diff bring back what a record prevented?** Read the decision records — ADRs, design docs,
`DECISIONS.md` — that name the files or types the diff touches. For each, ask what it **prevented**, not
only what it chose, and whether the diff reintroduces that. A diff that reverses a record without
superseding it is a finding; one that supersedes it in the same diff is not. Observed 2026-09-30: a
redesign gave its models default arguments pointing at shared real services — the exact coupling an
earlier ADR had been written to remove, so tests would touch real storage again.

**Claims the diff adds are checked like code.** Records, notes and comments added by the branch make
checkable statements — "never", "always", "off the main thread", "no full-resolution bitmap is held",
"the key distinguishes every case". Check each against **every** path in the diff, fallbacks included.
Observed 2026-09-30: an ADR in the diff under review claimed three things its own code did not do,
and the review — engine and door both — never opened it.

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
consistency   <n> split patterns · <n> hand-rolled idioms · <n> redundant state · <n> ownership   <or: skipped (--quick)>
records       <n> records read · <n> reintroduced · <n> false claims   <or: none touch the diff · skipped (--quick)>
tests         <n> added · <n> would not fail under their named mutation
security      <run | not triggered — and what would have triggered it>
worktree      <clean | uncommitted: file, file — the review is of the committed range>

CONFIRMED (n)   ← fixed before proceeding
- <finding> · <file:line> · <the fix>

PLAUSIBLE (n)   ← judged
- <finding> · fixed | refuted: <reason>

re-verified   <rows re-run, or: cosmetic only>
```

Then ask — **never chain**:

> "Review clean, verification evidence attached. Next is Phase 14 (`dev:pre-prod`), which pushes and
> opens the PR. Go?"

**When there is no PR to carry the report** — the range is already merged, or the base is a custom ref
that no PR targets — the report would otherwise live only in the chat. Offer to write it to
`docs/review/<YYYY-MM-DD>.md` on a branch in its own worktree (`shared/entry.md`'s write boundary), and
do **not** offer Phase 14: there is nothing to open. Observed 2026-09-30: a review of an
already-merged range was asked *"where have you documented that"*, and the answer was nowhere.

## Never

- **Never chain into Phase 14.** Opening a PR is a decision; `shared/entry.md` forbids chaining into
  a merge or a promotion.
- **Never report a clean gate on an empty diff** (Phase 2).
- **Never drop a finding silently** — refute it in writing or fix it (Phase 6).
- **Never accept an acceptance criterion on a claim** — point at a line or mark it missing.
- **Never let a correctness pass stand in for a security pass** when the diff triggers one.
- **Never block on a pre-existing problem the branch did not touch.** Say it in a sentence.
- **Never claim the engine ran when it did not.** Say "by hand" and mean it.
- **Never review a repo other than the resolved one** — and when the conversation names another, confirm
  which one is resolved before reading (Phase 2).
- **Never cite a line you have not opened** (Phase 3).

## Known limits

| | |
|---|---|
| Scope is the diff | A design flaw spread across untouched files is out of scope here — that is `dev:findings`. Phase 4b reads outside the diff, but only to judge the diff |
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

**Run 2026-09-12 twice, and 2026-09-30 over another repo's merged range** (`baseline...main`, a
take-home). The spec table ran against a README's required behaviours; the engine's findings needed
their line numbers remapped; the ADRs in the diff went unread, and a design discussion afterwards found
the ownership problem the review had split into four separate findings. Phases 4b's ownership lens and
4c came from that run. The `--quick` path and the re-verification trigger are still designed, not observed.
