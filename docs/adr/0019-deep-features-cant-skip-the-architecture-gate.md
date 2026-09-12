# 0019 — Deep features can't skip the architecture gate

Status:  Accepted
Date:    2026-09-11
Commit:  (this branch)  ·  `fix/deep-architecture-gate`

## Context

PR #50 (`feat: Dev Desk Mac app and the system-model page`, merged 2026-09-11) was a Deep-tier,
novel-design feature. Its run asked the developer only scope questions, then chose the project
shape, windows, state model, data seam, git reads, runner and platform itself, and built them. Its
own `## PIPELINE` admits the skip:

    Tier:    Deep
    Ran:     1, 2, 3, 4, 5 (scope only), 7, 8, 9, 10, 11, 12, 13, 14
    Skipped: 5's "ask for your approach" and 6 (architecture alternatives) — NOT put to the developer
             before building; a miss, recorded, …

Its "Architecture record (Phase 6, written after the fact)" lists seven decisions the developer did
not see until they were built.

`shared/pipeline.md` already put Deep-tier features under Phase 6's **When**. Four things let the
skip through anyway:

- **The heading said `(conditional)`.**
- **The Tier table's Deep row contradicted the When line.** It said the Phase 6 architects "stay
  independently conditional — Deep does not mandate them".
- **Neither line named the reasons the run used:** the scope questions had already happened, and the
  developer had asked it to go fast or use agents.
- **The audit accepted any skip with a reason.** `skills/audit/compliance_auditor.py` asks only that
  each phase in the tier's set (`TIER_REQUIRED_PHASES`) is run, or skipped with a reason, on every
  tier. Run against PR #50, it scored Phase 6 a legitimate `DECLARED_SKIP`. And the door never ran
  it: `skills/audit/SKILL.md` did not mention the script.

## Decision

**Phase 6 is required for Deep-tier features, in the rule and in the audit.** The developer approved
rule text plus an audit check on 2026-09-11.

**1. The rule** (`shared/pipeline.md`, still 995 lines):

- Phase 6's heading is `(required for Deep features)`. Its **When** runs it for every Deep-tier
  feature, any novel design, or when the developer asks. It says Phase 5's scope answers are not
  this gate, and that "go fast" and "use agents" change how it runs, never whether. A Deep feature
  skips it only after "lighter" at Deep's cost declaration, which makes the Tier Standard. Bugs,
  and work with one obvious shape that is not a Deep feature, still skip it.
- The cost declaration says a "lighter" answer makes the task Standard from then on.
- The Deep row says Phase 6 is required for every Deep feature. The Phase 2 explorers stay
  conditional, and Deep work that is not a feature and has one obvious shape (a fix, a migration, a
  rename) skips both.
- "The winning approach seeds Phase 7's plan" is gone. Phase 7 already says its plan is seeded by
  Phase 6's winning approach, and the line paid for the new text.

**2. The audit** (`skills/audit/compliance_auditor.py`). A PR gets a Critical alert, the phase
status `FORBIDDEN_SKIP` and a non-compliant verdict when all three hold:

- its title starts `feat:`, `feat(` or `feat!:`, the repo's conventional-commit feature form;
- its `Tier:` names Deep;
- it lists Phase 5 or 6 under `Skipped:`, with a reason or without one.

The alert:

    Critical: Deep-tier feature skipped Phase 6 (Architecture Alternatives). Phase 6 is required for
    Deep features; only "lighter" at the cost declaration skips it, and that changes Tier.

Phase 5's alert says instead that only a trivial change skips it, and a Deep feature is not one. A
`fix`, `chore`, `docs` or `refactor` title, or a tier without Deep, is audited as before. A bare
Phase 5 or 6 skip that the check flags is reported once, as the Critical, not also as a bare skip.

**What "names Deep" means.** Only `Tier:`'s first sentence is read, with its parenthetical reasons
removed. In each `·`-separated part the strictest whole tier word counts, case-insensitively:
Light (or Quick), Standard or Deep, the Right-Size table's names. The possessive `Deep's` names the
tier's cost, not a tier. So `Standard (moves) · Deep (auth flow)` and
`Standard, escalated to Deep in practice` are Deep, while
`Standard (answered "lighter" to Deep's cost)` and `Standard — lighter than Deep's cost` are
Standard. The strictest tier named governs, both for this check and for which phases the audit
requires.

The title comes from `gh pr view --json title` under `--pr`, or from a new `--title` flag for a body
given by `--file`, `--text` or stdin.

**3. The door runs the checker.** `skills/audit/SKILL.md` Step 1 now runs
`python3 ~/.claude/skills/dev/skills/audit/compliance_auditor.py --pr <N>`, the install path that
ADR 0010 requires, and `allowed-tools` lists `python3`. The door names the new classification and
says the checker's findings are the floor: the auditor's own reading may add to them, never clear
one.

**4. The parser reads this repo's own PR bodies.** Three gaps would have made the check unreliable
on them:

- **Wrapped fields.** A line indented further than the `Ran:`, `Skipped:` or `Gates:` line above
  it continues that field, until the next field line, a blank line or the fence. Before, it was
  dropped, or read as a field of its own when it held a colon.
- **Bold keys.** `**Tier: …**`, `**Ran:**` and `**Skipped:**` read as their plain forms.
- **The tier.** The whole-word rule above replaces a substring test that read "lighter" as Light
  and picked Light over Deep in `Light (…) · Deep (…)`.

## Rejected

- **Rule text only.** That is what failed. Phase 6's **When** already named Deep-tier features, and
  the run skipped it on reasons the text never ruled out. `docs/guide/CONTRIBUTING.md` names the
  pattern: gates that produce only a conversation get skipped and nobody notices.
- **A blocking check in `hooks/pr-gates.sh`**, refusing `gh pr create` when a Deep `feat` body skips
  Phase 5 or 6. Enforcement is deliberately honour-system, by the owner's call on 2026-08-04
  (`hooks/pr-gates.yml`'s header). The audit reports; people decide.
- **Relying on the agent to remember.** The run that skipped Phase 6 had the rule loaded. A memory
  note is one more piece of prose, and it lives on one machine and in one CLI.

## Consequences

- **The audit catches a skip after the fact, not before building.** By the time a PR body exists,
  the design is built. The rule text is the prevention. The audit makes a skip visible, and a reason
  no longer turns it into a legitimate declared skip.
- **A `feat` PR that really is a one-shape change must say Standard.** On a Deep feature, no reason
  under `Skipped:` clears Phase 5 or 6. The developer's "lighter" and a Standard `Tier:` do.
- **A mixed `Tier:` fails closed.** A `feat` PR with any Deep part is held to the Deep rule, even
  when its novel design sits in the Standard part. Real tier lines put Deep first or last
  (`Deep (security fix) · Standard (retirement)`, `Standard (moves) · Deep (security fix)`), so
  reading only the first part would depend on the order. `Tier: Deep → Standard` also reads as
  Deep: write the tier that was run.
- **The title decides what a feature is.** A Deep feature titled `fix:` or `refactor:` escapes the
  check, and so does a body audited with `--file` or `--text` and no `--title`. The door's default,
  `--pr`, reads the title.
- **Older PRs audit differently, and only for the better.** Across #46–#54 the parser changes
  removed hidden skips and added none. PR #49's bold fields are read, and its
  `Standard, escalated to Deep in practice` makes it Deep; it ran Phases 5 and 6, so it gets no
  alert, and its 14 hidden skips become 1, a missing `## VERIFICATION`. The wrapped Phase 16 of
  #50–#54 is a declared skip. A mixed `Light (…) · Deep (…)` line is audited against Deep's list.
- **Three limits remain.**
  - A tier word must come before the first `.`: `Standard. Deep for the auth part` reads as
    Standard.
  - A negation still names its tier: `Standard, not Deep` reads as Deep. That fails closed.
  - A reason must follow its phase number: `5 and 6 for the security fix (one shape)` reads as
    two bare skips, as #51 and #52 show. Neither is a `feat` PR, so the check is unaffected.
- **The compliance suite grows from 7 tests to 19.** Dated records keep 7:
  `tests/compliance/COMPLIANCE_VALIDATION.md` and `tests.yml`'s installation note.

## Evidence

```
python3 skills/audit/compliance_auditor.py --pr 50 --format json        # before
→ tier deep · Phase 5 MATCHED · Phase 6 DECLARED_SKIP "Reason: (architecture alternatives)"

python3 skills/audit/compliance_auditor.py --pr <N> --format json       # after, #46–#54
→ #50            feat, Deep        Phases 5 and 6 FORBIDDEN_SKIP · 2 Critical alerts · 16 declared
  #54            feat(desk), Deep  Phases 5 and 6 ran · no alert
  #51 #52 #53    fix / refactor, Deep                 · no alert
  #46 #47 #48    feat, Standard                       · no alert
  #49            feat, escalated to Deep              · read as Deep; ran 5 and 6, no alert
  #50's "Bare skip: Phase 5" alert is gone: the Critical reports that phase once

hidden skips, before → after
→ #49 [1–14] → [11] · #50 [16] → [] · #51 #52 [1–4, 7, 8, 16] → [1–4, 7, 8] · #54 [16] → []
  #53 bare [5, 16] → [5]. #46 [13], #47 [10] and #53 [1–4, 7, 8] are unchanged: those phases are
  missing from both Ran: and Skipped:

for f in tests/*/test_*.py; do PYTHONPATH=. python3 "$f" 2>&1 | tail -2; done
→ compliance 19/19 · rollback 5/5 · board 34/34 · project 16/16 · run 16/16 · state 17/17

the compliance suite against copies of the final auditor with one change undone each
→ check off (`if False and …`): 08, 09, 13, 16, 18, 19 fail · no continuation lines: 15 ·
  no bold keys: 16, 18 · the old substring tier: 17 (4 of 8 cases) ·
  first word only: 17 (2 cases), 18 · no single report: 19

wc -l shared/pipeline.md
→ 995 before and after

the run step of line-budget.yml, extracted and run with bash -eo pipefail
→ pipeline.md 995 / 995 — documented count and ceiling verified.   (exit 0)
```
