# Root Cause Analysis: Web MASTER_PROMPT Bootstrap Failures

**Date:** 2026-09-09  
**Analyst:** Claude Sonnet 4.5  
**Scope:** New project bootstrap path when ARCHITECTURE.md does not exist

---

## Executive Summary

The web MASTER_PROMPT bootstrap flow has **five critical gaps** that prevent it from working in new projects:

1. **Missing bootstrap trigger** — no automatic invocation when ARCHITECTURE.md is absent
2. **Ambiguous file creation** — MASTER_PROMPT says "pin decisions" but not "create the file"
3. **Pipeline asymmetry** — PROJECT_MAP.md has fallback creation logic, ARCHITECTURE.md does not
4. **Unclear invocation model** — documentation conflicts on whether this is manual or automatic
5. **Never validated** — the new-project path has never been exercised end-to-end

**Impact:** New projects cannot use dev-skill from day one. The pipeline expects ARCHITECTURE.md to exist (Phase 1) but provides no mechanism to create it.

---

## Evidence

### 1. SKILL.md Says It Should Be Automatic

**Location:** `./SKILL.md`, line 155

```markdown
Apply only when `ARCHITECTURE.md` is **missing** from the repo root 
(first feature on a new project), or when the user explicitly asks 
to revisit architecture.
```

**Finding:** The skill documentation clearly states MASTER_PROMPT should apply when ARCHITECTURE.md is missing. This implies automatic detection and application, not manual invocation.

**Gap:** Pipeline Phase 1 checks for ARCHITECTURE.md but does NOT trigger MASTER_PROMPT when absent.

---

### 2. Pipeline Expects But Never Creates ARCHITECTURE.md

**Location:** `./shared/pipeline.md`, Phase 1 (lines 176-179)

```markdown
1. Check for `PROJECT_MAP.md` → load `TECH_STACK`, `SYSTEM_FLOW`, `ORPHANS & PENDING`
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions
3. Check for `specs/[feature-slug].md` → if found, resume from existing spec
4. Report what was loaded: e.g. `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`
```

**Finding:** Phase 1 attempts to load ARCHITECTURE.md but has no fallback when it's missing.

**Comparison with PROJECT_MAP.md (Phase 2, line 189):**
```markdown
Read `PROJECT_MAP.md` if it exists — extract `TECH_STACK` and `SYSTEM_FLOW`. 
If absent, create it in Phase 7.
```

**Gap:** PROJECT_MAP.md has explicit creation logic (`create it in Phase 7`). ARCHITECTURE.md does not.

**Impact:** Pipeline will run with no architecture documentation, violating the "Memory Establishment" principle (Guiding Principles table, line 9).

---

### 3. MASTER_PROMPT Doesn't Explicitly Create Files

**Location:** `./web/MASTER_PROMPT.md`, line 3

```markdown
> **Use once per project** to lock architecture, conventions, and AI usage rules. 
> Pin decisions in `ARCHITECTURE.md` at the repo root. Per-feature prompts must 
> derive from the rules established here.
```

**Finding:** The instruction says "Pin decisions in `ARCHITECTURE.md`" but doesn't explicitly say:
- CREATE a file named `ARCHITECTURE.md`
- Write the following structure to that file
- Place it at the repo root as a write operation

**Observed Behavior in Reproductions:**

From `test-projects/nextjs-new/REPRODUCTION.md`:
- MASTER_PROMPT was invoked manually with explicit user prompt
- Generated comprehensive architecture content (App Router structure, data fetching, state management, styling, etc.)
- Content was documented in REPRODUCTION.md for analysis
- **NO ARCHITECTURE.md FILE WAS CREATED**

Directory listing after reproduction:
```bash
$ ls -la test-projects/nextjs-new/
total 48
-rw-r--r-- .gitkeep
-rw-r--r-- REPRODUCTION.md   # <-- Architecture content here
-rw-r--r-- package.json
```

**Gap:** Unclear whether MASTER_PROMPT should:
- a) Generate text response for user to manually create file
- b) Write ARCHITECTURE.md to disk automatically
- c) Be an interactive template that guides file creation

---

### 4. No Invocation Mechanism in Pipeline

**Finding:** Searched entire `./shared/pipeline.md` (995 lines) for MASTER_PROMPT references:

```bash
$ grep -i "MASTER_PROMPT\|Master Prompt" ./shared/pipeline.md
# (no results)
```

**Gap:** The pipeline has no phase that says:
- "If ARCHITECTURE.md is missing, invoke MASTER_PROMPT"
- "Phase 2 applies architecture prompts for new projects"
- "Generate ARCHITECTURE.md before continuing"

**What Phase 2 Actually Does (line 187-189):**
```markdown
1. Read `PROJECT_MAP.md` if it exists — extract `TECH_STACK` and `SYSTEM_FLOW`. 
   If absent, create it in Phase 7.
2. Ambiguity check
3. Time awareness
4. Scan root files to detect stack (package.json → Next.js/React/Vue, etc.)
```

Phase 2 detects the stack (Next.js, React, Vue) but doesn't trigger architecture generation.

---

### 5. Reproductions Confirm Content Quality, Not File Creation

**Test Projects Created:**
- `test-projects/nextjs-new/` — Next.js 14 App Router variant
- `test-projects/ios-new/` — iOS Swift/SwiftUI variant  
- `test-projects/android-new/` — Android Kotlin/Compose variant

**Reproduction Results:**

All three reproductions successfully generated comprehensive architecture plans:
- ✅ Stack detection worked (Next.js 14, iOS Swift, Android Kotlin)
- ✅ Phase-based implementation plans generated (Phase 0-4)
- ✅ All required topics covered (structure, data flow, state, styling, etc.)
- ✅ Risk documentation included
- ✅ Claude Code integration rules defined

**But:**
- ❌ No ARCHITECTURE.md files created in any test project
- ❌ Content only exists in REPRODUCTION.md (manual documentation)
- ❌ Pipeline never invoked automatically

From `build-progress.txt` (lines 57-62):
```
4. Need to investigate:
   - How these MASTER_PROMPTs are discovered/invoked in new projects
   - Whether pipeline Phase 1 handles missing ARCHITECTURE.md gracefully
   - If bootstrap flow needs explicit instructions or automation
```

**Observation:** The MASTER_PROMPT content is excellent and complete. The problem is not WHAT it generates, but WHEN and HOW it gets invoked and persisted.

---

## Root Causes Summary

| # | Root Cause | Evidence Location | Impact |
|---|---|---|---|
| 1 | **Missing Trigger Logic** | Pipeline Phase 1-2, SKILL.md line 155 | MASTER_PROMPT never runs automatically for new projects |
| 2 | **Ambiguous File Creation** | web/MASTER_PROMPT.md line 3 | Unclear if output should create file or return text |
| 3 | **Pipeline Asymmetry** | pipeline.md lines 177 vs 189 | PROJECT_MAP.md has fallback, ARCHITECTURE.md doesn't |
| 4 | **No Invocation Documentation** | All pipeline phases | No phase says "run MASTER_PROMPT when missing" |
| 5 | **Unvalidated Path** | documentation/WORKFLOW.md | New-project flow never tested end-to-end |

---

## Proposed Fix

### Fix 1: Add Bootstrap Trigger to Phase 2

**Location:** `./shared/pipeline.md`, Phase 2 (after stack detection, before Phase 3)

**Add:**
```markdown
5. **Architecture Bootstrap (new projects only):**
   If `ARCHITECTURE.md` is missing from repo root:
   - Apply MASTER_PROMPT variant matching detected stack:
     - Web (Next.js/React/Vue) → `web/MASTER_PROMPT.md`
     - Mobile (iOS/Android/KMP) → `mobile/MASTER_PROMPT.md`
   - Generate comprehensive architecture decisions
   - Write to `ARCHITECTURE.md` at repo root
   - Report: "Created ARCHITECTURE.md for new [stack] project"
   
   If `ARCHITECTURE.md` exists: skip this step and proceed to Phase 3.
```

**Rationale:** Phase 2 already detects stack and handles PROJECT_MAP.md fallback. Adding ARCHITECTURE.md creation here maintains symmetry and ensures architecture exists before Phase 3 (branch naming) begins.

---

### Fix 2: Make File Creation Explicit in MASTER_PROMPT

**Location:** `./web/MASTER_PROMPT.md`, header section

**Change from:**
```markdown
> **Use once per project** to lock architecture, conventions, and AI usage rules. 
> Pin decisions in `ARCHITECTURE.md` at the repo root.
```

**To:**
```markdown
> **Use once per project** to lock architecture, conventions, and AI usage rules. 
> **Output:** Create `ARCHITECTURE.md` at the repo root containing all architectural 
> decisions. This file becomes the source of truth for the project.

## Output Format

When invoked for a new project, create `ARCHITECTURE.md` with the following structure:

```markdown
# ARCHITECTURE.md

> Source of truth for architecture decisions in this [Next.js/React/Vue] project.
> Generated: [date]
> Last Updated: [date]

## Stack
[Framework, runtime, styling, deployment target]

## [App Router Structure / Component Architecture]
[Server vs client boundaries, route organization, etc.]

... (all sections from Phase 0-4 deliverables)
```
```

**Rationale:** Removes ambiguity. Makes it clear that MASTER_PROMPT's job is to CREATE a file, not just describe what should be in it.

---

### Fix 3: Add ARCHITECTURE.md Fallback to Phase 1

**Location:** `./shared/pipeline.md`, Phase 1 (line 177)

**Change from:**
```markdown
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions
```

**To:**
```markdown
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions.
   If absent, flag for creation in Phase 2 (bootstrap will run automatically).
```

**Rationale:** Makes Phase 1's expectations explicit and sets up Phase 2's bootstrap trigger.

---

### Fix 4: Update SKILL.md to Clarify Automatic Bootstrap

**Location:** `./SKILL.md`, line 155

**Change from:**
```markdown
Apply only when `ARCHITECTURE.md` is **missing** from the repo root 
(first feature on a new project), or when the user explicitly asks 
to revisit architecture.
```

**To:**
```markdown
**Automatic Application:** When `ARCHITECTURE.md` is missing from the repo root,
the pipeline automatically applies the appropriate MASTER_PROMPT during Phase 2
(Tech Stack & Project Discovery). This creates the architecture foundation for
new projects.

**Manual Re-architecture:** User can explicitly invoke MASTER_PROMPT to revisit
architecture decisions on existing projects.
```

**Rationale:** Clarifies that bootstrap is automatic, not manual. Users don't need to "apply" anything — the pipeline handles it.

---

## Validation Plan

To verify fixes work:

1. **Create fresh test projects** (no ARCHITECTURE.md, minimal package.json)
2. **Run pipeline Phase 1-2** on each test project
3. **Verify ARCHITECTURE.md created** with correct stack-specific content
4. **Verify Phase 3+ proceed** without errors
5. **Test stacks:**
   - Next.js 14 (App Router)
   - React (Vite)
   - Vue 3
   - iOS (Swift/SwiftUI)
   - Android (Kotlin/Compose)
   - KMP (multiplatform)

**Success Criteria:**
- [ ] ARCHITECTURE.md exists after Phase 2
- [ ] File contains stack-appropriate architecture decisions
- [ ] Pipeline continues to Phase 3+ without manual intervention
- [ ] Existing projects (with ARCHITECTURE.md) skip bootstrap cleanly

---

## Related Issues

- `documentation/WORKFLOW.md` line 80: "New-project path barely tested. The `ARCHITECTURE.md`-absent branch and both MASTER_PROMPTs [need validation]"
- Spec `001-new-project-bootstrap-path-validation` acceptance criteria #2: "The pipeline handles the absence of ARCHITECTURE.md gracefully"
- User story: "As a developer starting a new project, I want dev-skill to bootstrap the necessary architecture documentation so that I can use the full pipeline from day one"

---

## Conclusion

**Root Cause:** The web MASTER_PROMPT bootstrap fails because:
1. No automatic trigger exists when ARCHITECTURE.md is missing
2. File creation is implied, not explicit
3. Pipeline checks for the file but never creates it

**Proposed Solution:** Add bootstrap logic to Phase 2 that:
1. Detects missing ARCHITECTURE.md
2. Applies appropriate MASTER_PROMPT for detected stack
3. Writes ARCHITECTURE.md to disk
4. Reports completion before Phase 3

**Confidence:** HIGH — reproductions prove content generation works; only invocation and persistence are missing.

**Next Steps:** 
1. Implement Fix 1 (Phase 2 bootstrap trigger) — highest priority
2. Implement Fix 2 (explicit file creation in MASTER_PROMPT) — clarifies intent
3. Validate with all supported stacks (Next.js, React, Vue)
4. Repeat analysis for mobile MASTER_PROMPT (subtask-2-2)
