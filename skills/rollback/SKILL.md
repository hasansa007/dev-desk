---
name: rollback
description: >
  Recover from AI-driven changes that break production. Classifies the broken promotion into
  code-only, additive migration, or destructive migration, generates the appropriate recovery
  plan, pauses for human approval, and executes the revert with dual-branch synchronization and a
  verifiable audit trail.
  Trigger when user says "rollback", "revert production", "rollback prod", "undo the last deploy",
  "production is broken", "revert this release", or asks to recover from a bad deploy.
allowed-tools: [gh, git]
---

# Dev — Rollback & Recovery

Standalone recovery door for broken production deployments.

When Devin, Copilot Workspace, Claude Code, or any AI coding agent breaks production, developers
are left to manually investigate and repair the damage. `/dev:rollback` automates the recovery
pipeline while keeping human judgment strictly in control.

Its first job is **classification, not execution**: read the promotion diff, separate code from
schema changes, refuse destructive actions, and pause for explicit human approval before touching
any branch.

---

## The Classification Model

A rollback cannot be a simple `git revert`: Phase 16 applies schema **before** code, so a rollback
must reverse code **before** schema — and schema changes do not always reverse.

| Classification | Manifestation in Diff | Reversible? | Recovery Strategy |
|---|---|---|---|
| **Code-Only** | Only application files modified (`src/`, `components/`, `lib/`). No migration files. | **Yes, always** | Revert the promotion merge commit on the production branch. Deploying on merge redeploys the known-good code immediately. |
| **Additive Migration** | New tables, new nullable columns, new columns with defaults, new indexes. | **Yes**, code only | Old application code ignores new columns/tables. Revert application code while leaving schema forward. Verify backward compatibility before merge. |
| **Destructive Migration** | Dropped tables/columns, renamed columns, narrowed types, truncations, non-reversible backfills. | **NO via code revert** | **REFUSE automated code rollback.** Code rollback will crash against altered schema and cannot recover lost data. Explain Point-in-Time Restore (PITR) vs forward-fix migration. Require explicit confirmation. |

---

## Step 1 — Workspace & Branch Resolution

Always resolve the repository and branch model before running commands (`shared/entry.md`):

```bash
git remote get-url origin
git branch -r --format='%(refname:short)'
```

1. **Resolve branches:**
   - **`prod` branch:** The branch whose merge releases production (`main` / `master` or per release runbook).
   - **`pre-prod` branch:** `staging` → `develop` → `main`.
2. **Detect model:**
   - **Single-stage:** `prod == pre-prod` (e.g. `main` only).
   - **Two-stage:** `pre-prod` is `staging`/`develop` and `prod` is `main`.

**State the resolved branches explicitly:**
> "Rollback target: repo `<owner>/<repo>`, prod branch `<prod>`, pre-prod branch `<pre-prod>` (<single-stage | two-stage> model)."

---

## Step 2 — Identify the Broken Promotion

1. **Target Identification:**
   - If the user specifies a commit SHA or PR number, use it.
   - Otherwise, locate the most recent promotion commit on the production branch:
     ```bash
     git fetch origin <prod>
     git log -n 5 --oneline origin/<prod>
     ```
   - For merge commits, identify the merge SHA (`M`) and parent commits (`M^1` is current prod base, `M^2` is incoming head).
2. **Extract the Changeset Diff:**
   ```bash
   # If merge commit:
   git diff <SHA>^1..<SHA> --stat
   # If squash / standard commit:
   git diff <SHA>^..<SHA> --stat
   ```

---

## Step 3 — Classification Engine

Scan all changed files in the promotion diff for database migration paths across supported stacks:

### Migration Path Patterns
- **SQL / Supabase:** `**/migrations/*.sql`, `supabase/migrations/*.sql`
- **Prisma:** `prisma/migrations/**`
- **Drizzle:** `drizzle/*.sql`, `**/drizzle/migrations/**`
- **TypeORM / MikroORM:** `**/migrations/*.ts`, `**/migrations/*.js`
- **Python / Alembic / Django:** `alembic/versions/*.py`, `**/migrations/*.py`
- **Rails / Active Record:** `db/migrate/*.rb`
- **Go / Java (Flyway / Liquibase):** `db/migration/*.sql`, `db/changelog/**`

### Classification Rules

1. **Check for Migration Files:**
   - If zero migration files match: **Category 1: Code-Only**.
2. **If Migration Files Exist, Inspect SQL / Migration AST:**
   - Search for **Destructive Statements** (case-insensitive):
     - `DROP\s+TABLE`
     - `DROP\s+COLUMN`
     - `ALTER\s+TABLE\s+.*\s+DROP`
     - `ALTER\s+TABLE\s+.*\s+ALTER\s+COLUMN\s+.*\s+TYPE` (narrowing)
     - `TRUNCATE`
     - `RENAME\s+COLUMN`
     - `RENAME\s+TO`
     - Python/Prisma equivalents: `op.drop_column`, `op.drop_table`, `removeColumn`, `dropTable`
   - If destructive statements found: **Category 3: Destructive Migration**.
   - If only additive statements found (`CREATE TABLE`, `ADD COLUMN`, `CREATE INDEX`, nullable columns): **Category 2: Additive Migration**.

---

## Step 4 — Human Approval Gate (MANDATORY)

**Never execute a rollback autonomously.** Present the classification analysis and wait for developer confirmation:

```text
========================================================================
🚨 DEV:ROLLBACK — RECOVERY CLASSIFICATION & PLAN
========================================================================
Broken Promotion: <SHA> (<Commit Title>)
Author / Agent:   <Author>
Target Branch:    <prod> (syncing to <pre-prod>)

Classification:   <CODE-ONLY | ADDITIVE MIGRATION | DESTRUCTIVE MIGRATION>
Risk Level:       <LOW | MEDIUM | CRITICAL>

Diff Analysis:
- Total files modified: <N>
- Migration files detected: <M>
- Destructive operations: <None | List of destructive operations>

Proposed Recovery Action:
1. Cut recovery branch: rollback/<short-sha> from origin/<prod>
2. Revert commit <SHA> (<revert command>)
3. Run verification test suite (Phase 9/11)
4. Open Rollback PR targeting <prod>
5. Sync pre-prod branch to prevent bad commit re-introduction

========================================================================
Execute rollback plan? (yes / no / explain)
========================================================================
```

### Destructive Migration Guard
If classified as **Destructive Migration**, refuse automated revert and display:
> ⚠️ **CRITICAL WARNING:** This change executed destructive database operations.
> Reverting application code will NOT recover lost data and will cause runtime errors against the altered schema.
> 
> **Options:**
> 1. **Forward-Fix Migration (Recommended):** Write a new migration restoring or adapting the schema while preserving fresh data.
> 2. **Point-in-Time Restore (PITR):** Restore database to pre-incident backup. Warning: all transactions since `<timestamp>` will be permanently lost.
>
> Automated code rollback is BLOCKED without explicit manual confirmation.

---

## Step 5 — Revert Execution & Verification

Upon developer approval:

1. **Cut Isolated Rollback Branch:**
   ```bash
   git fetch origin
   git worktree add --no-track -b rollback/<short-sha> ~/.devdesk/wt/<repo>-rollback-<short-sha> origin/<prod>
   cd ~/.devdesk/wt/<repo>-rollback-<short-sha>    # a worktree of its own — the project folder is never switched (entry.md rule 4)
   ```
2. **Apply Revert:**
   ```bash
   # For a merge commit:
   git revert -m 1 <SHA> --no-edit
   # For a squash / normal commit:
   git revert <SHA> --no-edit
   ```
3. **Run Self-Verification (Phase 9):**
   - Execute local build and test suites (`npm run build`, `pytest`, `swift build`, etc.).
   - Ensure the revert introduces zero compilation or lint errors.

---

## Step 6 — Dual-Branch Synchronization (Prevent the Re-introduction Trap)

> **The trap:** Reverting the promotion on `prod` leaves the bad commit on `pre-prod`. The next
> regular promotion sees the bad commit on `pre-prod`, determines it is missing from `prod`, and
> **re-promotes the broken code**.

1. **Deploy to Prod:**
   - Push rollback branch and open Rollback PR targeting `<prod>`.
   - Include the **Rollback Evidence Trail** in the PR body.
   - Merge PR with confirmation.
2. **Synchronize Pre-Prod:**
   - In a two-stage repository, immediately open a synchronization PR or cherry-pick the revert commit onto `<pre-prod>`:
     ```bash
     git fetch origin
     git worktree add --no-track -b sync-rollback/<short-sha> ~/.devdesk/wt/<repo>-sync-rollback-<short-sha> origin/<pre-prod>
     cd ~/.devdesk/wt/<repo>-sync-rollback-<short-sha>
     git cherry-pick <REVERT_COMMIT_SHA>
     git push -u origin sync-rollback/<short-sha>
     gh pr create --base <pre-prod> --title "chore(sync): carry rollback of <short-sha> to pre-prod"
     ```
   - This prevents bad commits from being re-introduced in subsequent release cycles.

---

## Step 7 — Rollback Evidence Trail (PR Body Format)

Every rollback PR must include an audit trail:

````markdown
## ROLLBACK AUDIT TRAIL

- **Incident SHA:** `<BROKEN_SHA>`
- **Incident Summary:** `<Brief description of failure in production>`
- **Classification:** `<Code-Only | Additive Migration | Destructive Migration>`
- **Human Approver:** `<Username>` at `<Timestamp>`

## PIPELINE
Tier:    Standard
Ran:     Rollback Classification → Revert Verification → Dual-Branch Sync
Gates:   Classification Gate clean · Pre-flight check clean

## VERIFICATION
- Revert command: `git revert -m 1 <BROKEN_SHA>` (clean, no conflicts)
- Build check: `<Command>` (PASSED)
- Automated suite: `<Command>` (PASSED)

## HOW TO VERIFY PRODUCTION RESTORATION
1. Verify production deployment completes successfully
2. Run health check endpoint: `curl -I https://<prod-domain>/health`
3. Confirm error rate returns to baseline
````

---

## Next — ask, never stop flat

End the run by confirming production restoration and offering post-incident follow-up:

> "Rollback PR merged to `<prod>`. Revert is deploying to production.
> Pre-prod synchronization branch created.
> Would you like me to file a post-incident bug report via `/dev:create-bug` to investigate the root cause?"
