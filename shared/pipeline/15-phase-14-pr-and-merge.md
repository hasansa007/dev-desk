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
**When THIS merge releases prod** — single-branch repo, or a runbook that deploys on it — run
`skills/prod/prod-secrets.md` before merging: Phase 16 normally hosts it and is skipped here.

**Pre-merge gates (REQUIRED, before any merge)** — both are defined in full above. Run them against
the final PR diff (`git diff <BASE_BRANCH>...HEAD`); do not re-derive them here:

0. **Phase 12 — docs & decisions.** A PR without a `## DOCS` section is not ready to merge.
1. **Phase 13 — code review**, after the PR exists and before merging. Its resolution rules apply
   unchanged: fix CONFIRMED critical/important, refute PLAUSIBLE in one line, re-verify the
   affected Phase 11 rows if logic changed.
2. **Do NOT merge while any Critical/Important finding is open.** "The change looks small / I
   already self-reviewed / tests pass" does **not** waive this gate.
3. Review clean **and** the developer confirms → **merge → pre prod**.

After developer confirms:

### `## PIPELINE` — four lines that turn a skip into a written claim

Phase 12 works because a missing `## DOCS` is *visible*. The other twelve phases leave nothing
behind — which is how a 14-file rename ran end to end with no spec file (2026-08-04) and a branch
merged with its ADR unwritten (2026-07-31). Both were invisible **skips**, not wrong decisions.

```
## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9-14
Skipped: 6 (one obvious shape) · 8 (3 tasks, inline) · 16 (not promoting yet)
Gates:   10 flagged 2 → ran as rows 4-5 · 12 wrote the ADR · 13 clean (1 PLAUSIBLE refuted)
```

- **`Skipped:` carries a reason per phase, never a bare list.** "6, 8, 16" is not a claim anyone can
  falsify; "6 (one obvious shape)" is. Skipping is legitimate — skipping unexplained is not.
- **`Gates:` records what each gate CAUGHT, not that it ran.** `clean` is a real result and must be
  written; a gate missing from this line was not run.

`Gates:` is also this pipeline's only measurement — `gh pr list --json body | grep '^Gates:'` is
what makes a rule *removable* later. Rationale in `docs/guide/CONTRIBUTING.md` → *How to propose a change*.

**PR body format:**
```
## SUMMARY

 - <bullet points — what was built/fixed, any safety nets added>

## PIPELINE            ← tier, what ran, what was skipped AND WHY, what each gate caught
Tier:    <Light | Standard | Deep>
Ran:     <phase numbers>
Skipped: <phase (reason) · phase (reason)>   — or "none"
Gates:   <10 … · 12 … · 13 …>                — what each CAUGHT; "clean" is a result

## VERIFICATION

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

## PIPELINE

Tier:    <Light | Standard | Deep>
Ran:     <phase numbers>
Skipped: <phase (reason) · phase (reason)>
Gates:   <what each gate caught; "clean" is a result>

## VERIFICATION

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

