# Migration Classification & Recovery Strategy Validation

**Date:** 2026-09-10  
**Test Suite:** `test-projects/rollback/test_rollback_engine.py`  
**Scope:** Validate additive vs destructive migration detection and safety guards  
**Status:** ✅ VALIDATED

---

## 1. Overview

AI agents frequently couple schema changes with application code. When a change causes issues in production, blindly reverting code when migrations have already run can cause catastrophic downtime.

`dev:rollback` evaluates the SQL/migration AST before proposing any action, splitting migrations into **Additive** and **Destructive** categories.

---

## 2. Test Case A: Additive Migration Validation

### Input Diff
```sql
-- supabase/migrations/20260910000000_add_preferences.sql
ALTER TABLE users ADD COLUMN preferences JSONB NULL;
CREATE INDEX idx_users_preferences ON users(preferences);
```

### Classification Output
- **Files Detected:** `supabase/migrations/20260910000000_add_preferences.sql`
- **Destructive Statements Found:** 0
- **Classification:** `ADDITIVE_MIGRATION`
- **Reversible:** `YES, code only`
- **Risk Level:** `MEDIUM`

### Proposed Remediation Strategy
1. **Schema Remains Forward:** Do not run rollback migrations that drop the column or index.
2. **Backward-Compatibility Guarantees:** Old application code simply ignores the new `preferences` column.
3. **Revert Application Code:** Revert application commits that consumed the faulty logic.
4. **Verification:** Confirm pre-existing test suite passes against the forward schema.

### Execution Verdict: ✅ PASS
System correctly proposes leaving schema forward and safely reverting only the application code.

---

## 3. Test Case B: Destructive Migration Validation

### Input Diff
```sql
-- prisma/migrations/20260910_drop_token/migration.sql
ALTER TABLE "Account" DROP COLUMN "legacy_token";
DROP TABLE "OldSessions";
```

### Classification Output
- **Files Detected:** `prisma/migrations/20260910_drop_token/migration.sql`
- **Destructive Statements Found:**
  - `DROP COLUMN "legacy_token"`
  - `DROP TABLE "OldSessions"`
- **Classification:** `DESTRUCTIVE_MIGRATION`
- **Reversible:** `NO via code revert`
- **Risk Level:** `CRITICAL`

### Guard Enforcement & Warning
The system immediately halts and displays:
```text
⚠️ CRITICAL WARNING: DESTRUCTIVE MIGRATION DETECTED
========================================================================
This deployment executed destructive database operations:
- DROP COLUMN legacy_token
- DROP TABLE OldSessions

Reverting application code will NOT recover lost data and will cause
immediate crashes (old code expects 'legacy_token', but column is gone).

AUTOMATED ROLLBACK IS BLOCKED.

Remediation Options:
1. Forward-Fix Migration: Create a new migration restoring column/table
   structures and backfilling default values.
2. Point-in-Time Restore (PITR): Restore entire database to backup.
   Warning: Will discard all valid writes since incident.

Explicit confirmation required before proceeding.
========================================================================
```

### Execution Verdict: ✅ PASS
Automated code revert is strictly refused, data loss implications are explicitly surfaced, and manual confirmation is required.

---

## 4. Acceptance Criteria Checklist

- [x] Given an additive migration, when rollback is executed, then the system proposes backward-compatible remediation steps
- [x] Given a destructive migration, when rollback is executed, then the system warns about data implications and requires explicit confirmation
- [x] The rollback workflow pauses for human approval before executing any recovery action
