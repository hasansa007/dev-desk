---
name: audit
description: >
  Mechanical phase compliance auditor for dev-desk pipeline runs. Cross-references self-reported
  ## PIPELINE sections against actual tool-call and repository evidence (file writes, git operations,
  test execution, lint runs) to detect hidden skips, unverified claims, and silent omissions. Appends
  an objective ## COMPLIANCE section to the PR body.
  Trigger when the user says "audit compliance", "verify pipeline phases", "audit pipeline", "check
  compliance", "did we actually run all phases", "audit this PR", or before pre-prod merging to enforce
  phase execution integrity.
allowed-tools: [gh, git, python3]
---

# Dev — Phase Compliance Auditor

Mechanical compliance auditor that closes the **self-reporting trust gap** in `dev-desk`.

The dev-desk pipeline's core promise is **"enforcement, not just guidance"**. However, because the
`## PIPELINE` block in PR descriptions is written by the agent itself, an agent can claim it executed
phases that were silently bypassed, or omit skipped phases entirely from the `Skipped:` line.

`/dev:audit` cross-references claimed phases against verifiable evidence (git diffs, commit histories,
test execution records, documentation changes, and session tool calls), categorizes each phase, and
appends an objective **`## COMPLIANCE`** report to the PR body.

---

## The Compliance Classifications

| Classification | Meaning | Pipeline Rule | Action |
|---|---|---|---|
| **✅ MATCHED** | Phase is reported in `Ran:` AND substantiated by concrete evidence (file edits, test commands, git artifacts). | Full compliance. | Approved for merge. |
| **⏭️ DECLARED SKIP** | Phase is reported in `Skipped:` WITH an explanatory reason in parentheses (e.g. `6 (one obvious shape)`). | Legitimate skip under pipeline rules. | Approved for merge. |
| **⚠️ UNMATCHED** | Phase is claimed in `Ran:`, but required evidence was not found or is ambiguous. | Warning: potential unverified claim. | Investigate or request proof from agent. |
| **❌ HIDDEN SKIP** | Phase was required for the run tier but missing from both `Ran:` and `Skipped:`, OR claimed in `Ran:` with verifiable proof of complete omission. | Critical violation of pipeline rules. | **BLOCK PR MERGE** until addressed or legitimately declared. |
| **❌ BARE SKIP** | Phase is listed in `Skipped:` without an explanatory reason (e.g. `Skipped: 6, 8`). | Direct violation of Phase 14 (`"Skipped: carries a reason per phase, never a bare list"`). | Add explanatory reason. |
| **❌ FORBIDDEN SKIP** | Phase 5 or 6 is listed in `Skipped:` by a Deep-tier feature (a `feat` title and a `Tier:` naming Deep), with or without a reason. | Phase 6 is required for Deep features; only "lighter" at the cost declaration skips it, and that changes Tier. A Deep feature is never the trivial change Phase 5 exempts. | **Critical.** Run the phase, or correct `Tier:` if the developer answered "lighter". |

---

## Phase Evidence Signatures & Zero-Artifact Handling

To maintain a **false-positive rate below 10%**, the auditor distinguishes between phases that produce
hard filesystem/git artifacts and phases that legitimately operate through conversation or in-memory reasoning:

| Phase | Phase Name | Hard Evidence Required | Zero-Artifact Exemption Heuristic |
|---|---|---|---|
| **1** | Context Load | Reads to `CLAUDE.md`, `README.md`, `ARCHITECTURE.md`, or `docs/`. | Exempt in single-file hotfixes or when repo context is provided in prompt. |
| **2** | Tech Stack Discovery | Inspection of manifests (`package.json`, `Cargo.toml`, `go.mod`, etc.). | Exempt when stack is already known from issue metadata. |
| **3** | Git Branch Naming | Branch created from base; follows `<type>/<slug>` convention. | Branch existence in git is mandatory. |
| **4** | Investigation | Search/grep operations, log inspection, reading reproduction scripts. | Exempt if bug reproduction was trivial or provided by user. |
| **5** | Discuss Before Building | User interaction, prompts, architectural alignment questions. | **Conversational Gate:** Zero tool-call artifacts expected in git diff. Attested if Phases 7/9 proceed cleanly. |
| **6** | Architecture Alternatives | ADR file in `docs/` or design section in spec. | If skipped, MUST have parenthetical reason in `Skipped:`. A Deep-tier feature may not skip it at all (Forbidden Skip). |
| **7** | Plan Output | Spec file in `specs/` or `docs/superpowers/specs/`, or a structured plan in chat. | Written plan artifact or structured prompt outline. |
| **8** | Task Breakdown | Checklists, subtasks in plan, or phased task list. | Inline breakdown accepted; exempt on Light tier. |
| **9** | Implement | Modified source code in `git diff` (excluding docs/specs/tests). | **Mandatory:** Non-empty git diff outside documentation. |
| **10** | Pre-PR Quality Checks | Linter/static analysis tool execution, or `Gates: 10 clean`. | Tool call in transcript, or verified clean in PR Gates. |
| **11** | Verification Gate | Executable test runs, test suite output, new/updated tests in diff. | **Mandatory:** Real command output in `## VERIFICATION` or test suite artifacts. |
| **12** | Docs & Decisions Gate | `## DOCS` block in PR body + docs modified or explicit "none needed" rationale. | **Mandatory:** `## DOCS` section is required on every PR. |
| **13** | Code Review Gate | Self-review findings addressed, `Gates: 13 clean` or list of refuted items. | Claim in `Gates:` line or review transcript. |
| **14** | PR Creation → Pre Prod | PR created with all required sections (`## SUMMARY`, `## PIPELINE`, etc.). | PR exists on GitHub. |

---

## Step 1 — Target & Evidence Discovery

The auditor operates in two modes:

### Mode A: Post-Hoc / Git & PR Mode (Default)
When auditing a branch or existing PR:
1. Fetch PR body or staged PR text:
   ```bash
   gh pr view <PR_NUMBER> --json body,headRefName,baseRefName
   ```
2. Extract git diff against base branch:
   ```bash
   git fetch origin <BASE_BRANCH>
   git diff origin/<BASE_BRANCH>...HEAD --stat
   git log --oneline origin/<BASE_BRANCH>..HEAD
   ```
3. Run the checker. It applies Steps 2–4 and prints the `## COMPLIANCE` section:
   ```bash
   python3 ~/.claude/.dev-root/skills/audit/compliance_auditor.py --pr <PR_NUMBER>
   # no PR yet: --file <body.md> --title "<PR title>" — the title is what marks a feat PR
   # --append-pr writes the section into the PR (Step 5); --format json gives the raw verdict
   ```
   Its findings are the floor: your own read of the evidence may add to them, never clear one.

### Mode B: In-Session / Transcript Mode
When auditing an active session with execution logs:
1. Inspect tool calls in session transcript (`run_command`, `view_file`, `write_to_file`).
2. Map tool invocations directly to phase activities.

---

## Step 2 — Parse Self-Reported `## PIPELINE`

Extract the 4 key pipeline fields from the PR body:
```text
## PIPELINE
Tier:    <Light | Standard | Deep>
Ran:     <comma/hyphen separated phase numbers>
Skipped: <semicolon/bullet/middot separated skipped phases with reasons>
Gates:   <gate outcomes>
```

1. **Parse `Ran:`**: Expand ranges (e.g. `1-5, 7, 9-14` → `{1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14}`).
2. **Parse `Skipped:`**:
   - Extract phase numbers and reasons: `6 (one obvious shape) · 8 (3 tasks, inline) · 16 (not promoting yet)`.
   - Flag any **bare skips** missing parentheses (e.g. `Skipped: 6, 8`).
3. **Parse `Gates:`**: Extract records for Gate 10, Gate 12, Gate 13.
4. **Identify Undecided Phases**: Any phase from the active tier's required set not in `Ran:` and not in `Skipped:` is immediately marked **Hidden Skip**.

---

## Step 3 — Mechanical Evidence Cross-Referencing

Cross-reference each claimed phase against the collected evidence:

1. **Phase 9 (Implement):**
   - Check `git diff --name-only origin/<BASE_BRANCH>...HEAD`.
   - If only docs or specs changed and Phase 9 is claimed as a code feature, flag for inspection. If code changed, mark **MATCHED**.
2. **Phase 11 (Verification Gate):**
   - Inspect `## VERIFICATION` section of PR body.
   - Does it contain real command outputs and test counts?
   - Were test files executed or added in the diff?
   - If `## VERIFICATION` is empty, placeholder (`- <real command output>`), or omitted: **FLAG AS HIDDEN SKIP / UNMATCHED**.
3. **Phase 12 (Docs Gate):**
   - Does the PR body contain a `## DOCS` section?
   - Does it list updated documentation/ADRs, or does it carry the required Phase 12 `"none needed — checked: ..."` statement?
   - If missing or uncompleted template text: **FLAG AS VIOLATION**.
4. **Phase 10 (Quality Checks):**
   - Check `Gates:` line in `## PIPELINE`. Does it mention `10`?
5. **Phase 13 (Code Review):**
   - Check `Gates:` line in `## PIPELINE`. Does it mention `13`?

---

## Step 4 — Generate `## COMPLIANCE` Audit Report

Compute the Compliance Score:
$$\text{Compliance Score} = \frac{\text{Matched Phases} + \text{Declared Skips}}{\text{Total Evaluated Phases}} \times 100\%$$

Format the audit trail to append to the PR body:

````markdown
## COMPLIANCE

| Phase | Phase Name | Status | Evidence / Notes |
|---|---|---|---|
| 1 | Context Load | ✅ Matched | Inspected repository structure and configs |
| 2 | Tech Stack Discovery | ✅ Matched | Detected dependencies in manifests |
| 3 | Git Branch Naming | ✅ Matched | Branch `feature/XYZ` cut from `main` |
| 4 | Investigation | ✅ Matched | Grep/diff analysis logged |
| 5 | Discuss Before Building | ✅ Matched | Conversational gate attested |
| 6 | Architecture Alternatives | ⏭️ Declared Skip | `(one obvious shape)` — legitimate reason |
| 7 | Plan Output | ✅ Matched | Spec and implementation plan verified |
| 8 | Task Breakdown | ⏭️ Declared Skip | `(inline checklist)` — legitimate reason |
| 9 | Implement | ✅ Matched | 4 source files modified (+320 / -14) |
| 10 | Pre-PR Quality Checks | ✅ Matched | Linter clean (`Gates: 10 clean`) |
| 11 | Verification Gate | ✅ Matched | 5/5 automated tests passed |
| 12 | Docs & Decisions Gate | ✅ Matched | `README.md` and `COMMANDS.md` updated |
| 13 | Code Review Gate | ✅ Matched | AI self-review clean (`Gates: 13 clean`) |
| 14 | PR Creation | ✅ Matched | PR formatted with required sections |

**Audit Result:** 100% Compliant (12 Matched, 2 Declared Skips, 0 Hidden Skips).
````

### If Hidden Skips or Violations are Detected:

````markdown
## COMPLIANCE
⚠️ **COMPLIANCE ALERT: 1 Hidden Skip Detected**

| Phase | Phase Name | Status | Evidence / Notes |
|---|---|---|---|
| 11 | Verification Gate | ❌ Hidden Skip | Claimed in `Ran:` but `## VERIFICATION` contains placeholder text and no test runs were executed. |

**Remediation:**
Run Phase 11 test suite (`python3 test_runner.py`), paste real results into `## VERIFICATION`, or move Phase 11 to `Skipped:` with an explicit explanation.
````

---

## Step 5 — PR Integration

When invoked on an existing PR, update the PR body to include the `## COMPLIANCE` section:
```bash
gh pr edit <PR_NUMBER> --body "$UPDATED_BODY"
```

Or during Phase 14 (`pre-prod`), run `/dev:audit` as part of the pre-merge gate suite to guarantee that self-reported claims are mechanically verified before the PR is merged.

---

## Next — ask, never stop flat

End the run by presenting the audit verdict (`entry.md` → *Never end silently*):

> "Audit complete: `<Score>%` compliance (`<N>` matched, `<S>` declared skips, `<H>` hidden skips).
> Report appended to PR `#<PR_NUMBER>`.
> Ready to proceed with `/dev:pre-prod` merge, or would you like to address the audit findings first?"
