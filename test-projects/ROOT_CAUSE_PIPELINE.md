# Root Cause Analysis: Pipeline Phase 1 Context Load Behavior

**Date:** 2026-09-10  
**Analyst:** Claude Sonnet 4.5  
**Scope:** Pipeline Phase 1 behavior when ARCHITECTURE.md is missing  
**Focus:** New project bootstrap gap analysis

---

## Executive Summary

Pipeline Phase 1 (Context Load) has **three critical asymmetries** that prevent graceful handling of new projects:

1. **Silent failure mode** — Phase 1 checks for ARCHITECTURE.md but doesn't specify behavior when absent
2. **Asymmetric fallback logic** — PROJECT_MAP.md has creation fallback, ARCHITECTURE.md does not
3. **No new-project detection** — Phase 1 cannot distinguish between "missing file (new project)" and "missing file (corrupted project)"

**Impact:** New projects proceed through the pipeline WITHOUT architecture documentation, violating the "Memory Establishment" guiding principle. The pipeline continues as if the project were mature but incomplete, rather than new and uninitialized.

---

## Evidence

### 1. Phase 1 Documentation is Silent on Missing Files

**Location:** `shared/pipeline.md` lines 168-181

```markdown
## Phase 1 — Context Load

Runs before everything else. Reads persistent project context to skip re-discovery.

1. Check for `PROJECT_MAP.md` → load `TECH_STACK`, `SYSTEM_FLOW`, `ORPHANS & PENDING`
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions
3. Check for `specs/[feature-slug].md` → if found, resume from existing spec (skip Phase 7; for BUGS, Phase 4's reproduce-first step is never skipped — a spec is a plan, not a reproduction)
4. Report what was loaded: e.g. `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`

If a spec is found and Phase 8 or Phase 9 is the next step, skip straight there.
```

**Finding:** Phase 1 says "Check for" and "load" but does NOT specify:
- What to do if `ARCHITECTURE.md` is missing
- Whether to fail, warn, or silently continue
- Whether missing file is an error or expected state
- How to communicate missing context to subsequent phases

**Expected Behavior (undefined):**
- Option A: Fail fast → "ARCHITECTURE.md required, run MASTER_PROMPT first"
- Option B: Warn and continue → "ARCHITECTURE.md missing, proceeding with limited context"
- Option C: Auto-bootstrap → "ARCHITECTURE.md missing, creating from MASTER_PROMPT"
- Option D: Silent continue → (what currently happens)

**Actual Behavior:** Based on reproduction evidence, Phase 1 silently continues without ARCHITECTURE.md, then later phases operate without architectural context.

---

### 2. Asymmetric Fallback Logic with PROJECT_MAP.md

**Evidence:** Compare Phase 1 (ARCHITECTURE.md) vs Phase 2 (PROJECT_MAP.md)

**Phase 1 (line 176):**
```markdown
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions
```

**Phase 2 (line 189):**
```markdown
1. Read `PROJECT_MAP.md` if it exists — extract `TECH_STACK` and `SYSTEM_FLOW`. 
   If absent, create it in Phase 7.
```

**Finding:** 
- `PROJECT_MAP.md`: **Explicit fallback** → "If absent, create it in Phase 7" ✅
- `ARCHITECTURE.md`: **No fallback** → Silent gap ❌

**Why This Asymmetry Exists:**

From Phase 2's PROJECT_MAP.md handling:
- PROJECT_MAP.md can be **derived** from Phase 2 discovery (scan files, detect stack, build SYSTEM_FLOW)
- PROJECT_MAP.md creation is **mechanical** — no architectural decisions required
- Phase 7 (Create Spec) is the right place to create it because context is fully gathered

From Phase 1's ARCHITECTURE.md handling:
- ARCHITECTURE.md cannot be **derived mechanically** — requires architectural decisions
- ARCHITECTURE.md creation needs **MASTER_PROMPT** invocation (not a phase step)
- No phase currently owns "bootstrap architecture for new projects"

**Gap:** The asymmetry is intentional (PROJECT_MAP.md is derivable, ARCHITECTURE.md is not), BUT Phase 1 provides no guidance on what to do when ARCHITECTURE.md is absent.

---

### 3. No New-Project Detection

**Finding:** Phase 1 has no logic to distinguish:

| Scenario | ARCHITECTURE.md | PROJECT_MAP.md | Interpretation |
|---|---|---|---|
| **New project** | ❌ Missing | ❌ Missing | Needs bootstrap |
| **Corrupted project** | ❌ Missing | ✅ Exists | Needs recovery |
| **Partial migration** | ❌ Missing | ✅ Exists | Needs architecture adoption |
| **Mature project** | ✅ Exists | ✅ Exists | Normal operation |

**Gap:** Phase 1 cannot tell the difference between:
- **New project** (never had ARCHITECTURE.md) → should trigger bootstrap
- **Broken project** (had ARCHITECTURE.md, now missing) → should fail or warn

**Evidence from Reproductions:**

From `test-projects/nextjs-new/REPRODUCTION.md`:
```bash
# New project state (before MASTER_PROMPT)
$ ls -la test-projects/nextjs-new/
-rw-r--r-- .gitkeep
-rw-r--r-- package.json

# Neither ARCHITECTURE.md nor PROJECT_MAP.md exists
# Pipeline would proceed to Phase 2 with NO context loaded
```

**Impact:** Phase 1 report would say:
```
"Loaded: Nothing. No ARCHITECTURE, no PROJECT_MAP, no existing spec."
```

But Phase 2+ would continue as if this were normal, rather than triggering new-project bootstrap.

---

### 4. Phase 1 Report Template is Optimistic

**Location:** `shared/pipeline.md` line 179

```markdown
4. Report what was loaded: e.g. `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`
```

**Finding:** The example report assumes **success case** only:
- "Loaded PROJECT_MAP + ARCHITECTURE" — both files exist ✅
- No example for partial load: "Loaded PROJECT_MAP. ARCHITECTURE missing."
- No example for empty load: "No context files found (new project?)."

**Gap:** Phase 1's reporting doesn't communicate new-project state to developer or downstream phases.

---

### 5. Guiding Principles Violation

**Evidence:** `shared/pipeline.md` lines 9-17 (Guiding Principles table)

```markdown
| Principle | Source | Rule |
|---|---|---|
| **Memory Establishment** | Planning Protocol | Maintain `PROJECT_MAP.md` with `TECH_STACK`, `SYSTEM_FLOW`, and `ORPHANS & PENDING`. Read it before acting; update it after. |
```

**Finding:** "Memory Establishment" principle requires maintaining PROJECT_MAP.md but makes NO mention of ARCHITECTURE.md.

**Cross-Reference with SKILL.md:** (from ROOT_CAUSE_WEB.md, line 29)

```markdown
Apply only when `ARCHITECTURE.md` is **missing** from the repo root 
(first feature on a new project), or when the user explicitly asks 
to revisit architecture.
```

**Gap:** 
- SKILL.md says ARCHITECTURE.md is fundamental for new projects
- Pipeline Guiding Principles only mention PROJECT_MAP.md
- Phase 1 checks for ARCHITECTURE.md but doesn't enforce it

**Conclusion:** ARCHITECTURE.md is treated as **optional context** rather than **required foundation** by the pipeline, even though SKILL.md and MASTER_PROMPTs treat it as essential.

---

## Root Causes Summary

| # | Root Cause | Evidence Location | Impact |
|---|---|---|---|
| 1 | **Silent Failure Mode** | Phase 1 lines 176-179 | Missing ARCHITECTURE.md doesn't trigger any action |
| 2 | **Asymmetric Fallback Logic** | Phase 1 line 177 vs Phase 2 line 189 | PROJECT_MAP.md has fallback, ARCHITECTURE.md doesn't |
| 3 | **No New-Project Detection** | Phase 1 entire section | Cannot distinguish new project from broken project |
| 4 | **Optimistic Reporting** | Phase 1 line 179 | Report template assumes files exist |
| 5 | **Guiding Principles Gap** | Principles table lines 9-17 | ARCHITECTURE.md not mentioned in Memory Establishment |

---

## Behavioral Analysis: What Actually Happens

### Scenario 1: New Project (No Context Files)

**Input:**
```bash
$ ls -la
-rw-r--r-- package.json       # Next.js project
# No ARCHITECTURE.md
# No PROJECT_MAP.md
# No specs/
```

**Phase 1 Execution:**
1. Check for `PROJECT_MAP.md` → ❌ Not found
2. Check for `ARCHITECTURE.md` → ❌ Not found
3. Check for `specs/[feature-slug].md` → ❌ Not found
4. Report: `"No context loaded. Starting from scratch."`

**Phase 2 Execution:**
1. Read `PROJECT_MAP.md` → ❌ Not found → "create it in Phase 7" (deferred)
2. Scan root files → ✅ package.json found → detect Next.js
3. Continue with stack detection...

**Result:**
- Pipeline proceeds to Phase 3+ **without ARCHITECTURE.md**
- PROJECT_MAP.md will be created in Phase 7 (deferred)
- ARCHITECTURE.md is **never created** (no fallback exists)

**Violation:**
- "Memory Establishment" principle not satisfied (no architecture context)
- Per-feature prompts have no architecture to derive from (MASTER_PROMPT says "Per-feature prompts must derive from the rules established here")

---

### Scenario 2: Partial Context (PROJECT_MAP.md Exists)

**Input:**
```bash
$ ls -la
-rw-r--r-- package.json
-rw-r--r-- PROJECT_MAP.md     # Created by previous run
# No ARCHITECTURE.md
```

**Phase 1 Execution:**
1. Check for `PROJECT_MAP.md` → ✅ Found → load `TECH_STACK`, `SYSTEM_FLOW`
2. Check for `ARCHITECTURE.md` → ❌ Not found
3. Report: `"Loaded PROJECT_MAP. No ARCHITECTURE found."`

**Result:**
- Pipeline has TECH_STACK and SYSTEM_FLOW (from PROJECT_MAP.md)
- Pipeline has **no architectural decisions** (no ARCHITECTURE.md)
- Phases proceed with partial context

**Problem:** This state is **indistinguishable from new project** to downstream phases:
- Is this a new project that needs architecture bootstrap?
- Is this a project where ARCHITECTURE.md was deleted/lost?
- Is this a project that never used ARCHITECTURE.md?

Phase 1 cannot answer these questions.

---

### Scenario 3: Full Context (Both Files Exist)

**Input:**
```bash
$ ls -la
-rw-r--r-- package.json
-rw-r--r-- PROJECT_MAP.md
-rw-r--r-- ARCHITECTURE.md
```

**Phase 1 Execution:**
1. Check for `PROJECT_MAP.md` → ✅ Found → load context
2. Check for `ARCHITECTURE.md` → ✅ Found → load architecture
3. Report: `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`

**Result:**
- ✅ Full context available
- ✅ Pipeline proceeds with complete memory
- ✅ This is the **only scenario Phase 1 is designed for**

---

## Comparison with Other Context Files

### PROJECT_MAP.md Handling (Well-Defined)

**Phase 1:** Check for it  
**Phase 2:** "If absent, create it in Phase 7"  
**Phase 7:** Create it with gathered context  
**Result:** ✅ Guaranteed to exist by Phase 8

### ARCHITECTURE.md Handling (Undefined)

**Phase 1:** Check for it  
**Phase 2:** (silent, no mention)  
**Phase 7:** (silent, no mention)  
**Result:** ❌ Never created if missing

### specs/[feature-slug].md Handling (Conditional)

**Phase 1:** "If found, resume from existing spec (skip Phase 7)"  
**Phase 7:** Create new spec if none exists  
**Result:** ✅ Clear create-or-resume logic

**Finding:** ARCHITECTURE.md is the ONLY context file with no fallback creation logic.

---

## Why This Matters: Impact on Pipeline Phases

### Phase 3 — Branch Naming
- **Needs:** Feature context (has it), conventions (missing from ARCHITECTURE.md)
- **Impact:** Branch names may not follow project conventions

### Phase 4 — Investigation & Reproduce
- **Needs:** Architecture context to understand what "working" looks like
- **Impact:** Bug reproduction may miss architectural constraints

### Phase 5 — Discuss Before Building
- **Needs:** Architectural constraints to evaluate approach options
- **Impact:** May propose solutions that violate undocumented architecture

### Phase 6 — Architecture Alternatives
- **Needs:** Existing architecture decisions to ensure consistency
- **Impact:** May propose alternatives that conflict with unstated principles

### Phase 7 — Create Spec
- **Needs:** Architecture to derive feature implementation from
- **Impact:** Spec may omit critical architectural integration points

### Phase 8+ — Implementation
- **Needs:** Style guide, patterns, conventions from ARCHITECTURE.md
- **Impact:** Code may not follow project patterns (no source of truth)

**Conclusion:** Missing ARCHITECTURE.md degrades EVERY phase after Phase 1.

---

## Proposed Fix

### Fix 1: Add New-Project Detection to Phase 1

**Location:** `shared/pipeline.md` Phase 1, after step 2

**Add:**
```markdown
2. Check for `ARCHITECTURE.md` → load architectural decisions and conventions.
   
   **If absent:**
   - Check if this is a new project (neither ARCHITECTURE.md nor PROJECT_MAP.md exists)
   - If new project: flag for architecture bootstrap in Phase 2
   - If existing project (PROJECT_MAP.md exists): warn that ARCHITECTURE.md is missing and may need recovery
   
   Report new-project state: "New project detected. Architecture will be generated in Phase 2."
   Report missing-arch state: "WARNING: ARCHITECTURE.md missing from existing project."
```

**Rationale:** 
- Distinguishes new projects from broken projects
- Sets up Phase 2 bootstrap trigger
- Provides clear signal to developer

---

### Fix 2: Update Phase 1 Reporting to Handle All States

**Location:** `shared/pipeline.md` Phase 1, step 4

**Change from:**
```markdown
4. Report what was loaded: e.g. `"Loaded PROJECT_MAP + ARCHITECTURE. No existing spec found."`
```

**To:**
```markdown
4. Report what was loaded:
   - Full context: "Loaded PROJECT_MAP + ARCHITECTURE. Ready to proceed."
   - Partial context (PROJECT_MAP only): "Loaded PROJECT_MAP. ARCHITECTURE missing (will warn)."
   - New project (neither): "New project detected. Bootstrap will run in Phase 2."
   - Spec resumption: "Loaded PROJECT_MAP + ARCHITECTURE. Resuming from existing spec."
```

**Rationale:** 
- Reports actual state, not optimistic assumption
- Communicates new-project detection clearly
- Sets expectations for Phase 2 behavior

---

### Fix 3: Elevate ARCHITECTURE.md in Guiding Principles

**Location:** `shared/pipeline.md` Guiding Principles table

**Change:**
```markdown
| **Memory Establishment** | Planning Protocol | Maintain `PROJECT_MAP.md` with `TECH_STACK`, `SYSTEM_FLOW`, and `ORPHANS & PENDING`. Read it before acting; update it after. |
```

**To:**
```markdown
| **Memory Establishment** | Planning Protocol | Maintain `PROJECT_MAP.md` (tech stack, system flow) and `ARCHITECTURE.md` (architectural decisions, conventions). Read before acting; update after. For new projects, generate ARCHITECTURE.md via MASTER_PROMPT before first feature. |
```

**Rationale:** 
- Elevates ARCHITECTURE.md to same status as PROJECT_MAP.md
- Makes new-project requirement explicit
- Aligns Guiding Principles with SKILL.md and MASTER_PROMPT expectations

---

### Fix 4: Add Bootstrap Hook Between Phase 1 and Phase 2

**Location:** `shared/pipeline.md`, new section between Phase 1 and Phase 2

**Add:**
```markdown
## Phase 1.5 — Architecture Bootstrap (New Projects Only)

**Trigger:** Phase 1 detected missing ARCHITECTURE.md AND missing PROJECT_MAP.md (new project state).

**Purpose:** Generate foundational architecture before Phase 2 discovery begins.

**Process:**
1. Confirm new-project state: no ARCHITECTURE.md, no PROJECT_MAP.md, minimal repo structure
2. Run quick stack detection (same as Phase 2 step 4, but lightweight):
   - Scan for `package.json` → web stack likely
   - Scan for `*.xcodeproj`, `build.gradle*` → mobile stack likely
3. Invoke appropriate MASTER_PROMPT:
   - Web (Next.js/React/Vue) → `web/MASTER_PROMPT.md`
   - Mobile (iOS/Android/KMP) → `mobile/MASTER_PROMPT.md` with variant selection
4. Write generated architecture to `ARCHITECTURE.md` at repo root
5. Report: "Created ARCHITECTURE.md for new [stack] project. Proceeding to Phase 2."

**Skip conditions:**
- If ARCHITECTURE.md exists → skip entirely
- If PROJECT_MAP.md exists but ARCHITECTURE.md missing → skip and warn (not a new project, may be broken)

**Rationale:** New projects need architecture foundation before discovery (Phase 2) can be effective.
```

**Rationale:** 
- Fills the gap between Phase 1 detection and Phase 2 execution
- Isolates bootstrap logic (doesn't bloat Phase 2)
- Explicit skip conditions prevent overwriting existing architecture

---

## Alternative Approaches Considered

### Alternative A: Move Bootstrap to Phase 2

**Pros:**
- Phase 2 already does stack detection
- Symmetry with PROJECT_MAP.md fallback (also in Phase 2)
- No new phase number needed

**Cons:**
- Phase 2 is already complex (14+ steps in current version)
- Bootstrap logic is fundamentally different from discovery
- Harder to skip cleanly for existing projects

**Verdict:** Could work, but Phase 1.5 is cleaner separation of concerns.

---

### Alternative B: Make ARCHITECTURE.md Fully Optional

**Pros:**
- Simplifies pipeline (one less required file)
- Reduces ceremony for small projects

**Cons:**
- Violates SKILL.md and MASTER_PROMPT expectations
- Defeats purpose of dev-skill (architecture-driven development)
- Every phase after Phase 1 operates with degraded context
- User story explicitly requires: "bootstrap necessary architecture documentation"

**Verdict:** Not viable. ARCHITECTURE.md is fundamental to dev-skill's value proposition.

---

### Alternative C: Fail Phase 1 When ARCHITECTURE.md Missing

**Pros:**
- Forces explicit architecture setup
- Clear error message: "Run MASTER_PROMPT first"

**Cons:**
- Poor developer experience (extra manual step)
- Defeats "works from day one" goal from spec
- User story requires: "use the full pipeline from day one" (not "run MASTER_PROMPT then use pipeline")

**Verdict:** Violates acceptance criteria #2: "handles absence gracefully" (failing is not graceful).

---

## Validation Plan

### Test 1: New Project Detection

**Setup:**
```bash
mkdir -p test-validation/new-project
cd test-validation/new-project
echo '{"name": "test"}' > package.json
# No ARCHITECTURE.md, no PROJECT_MAP.md
```

**Run:** Phase 1

**Expected Output:**
```
Phase 1 — Context Load
- PROJECT_MAP.md: Not found
- ARCHITECTURE.md: Not found
- New project detected (no context files exist)
- Architecture bootstrap will run in Phase 1.5/2

Status: NEW_PROJECT
```

---

### Test 2: Broken Project Detection

**Setup:**
```bash
mkdir -p test-validation/broken-project
cd test-validation/broken-project
echo '# PROJECT_MAP.md' > PROJECT_MAP.md
# PROJECT_MAP.md exists, but ARCHITECTURE.md missing
```

**Run:** Phase 1

**Expected Output:**
```
Phase 1 — Context Load
- PROJECT_MAP.md: Loaded (TECH_STACK, SYSTEM_FLOW)
- ARCHITECTURE.md: Not found
- WARNING: Existing project missing ARCHITECTURE.md (recovery needed?)

Status: PARTIAL_CONTEXT
```

---

### Test 3: Mature Project (No Changes)

**Setup:**
```bash
mkdir -p test-validation/mature-project
cd test-validation/mature-project
echo '# PROJECT_MAP.md' > PROJECT_MAP.md
echo '# ARCHITECTURE.md' > ARCHITECTURE.md
```

**Run:** Phase 1

**Expected Output:**
```
Phase 1 — Context Load
- PROJECT_MAP.md: Loaded
- ARCHITECTURE.md: Loaded
- Full context available

Status: READY
```

---

## Related Findings

### From ROOT_CAUSE_WEB.md

**Root Cause #3 (line 166):**
> **Pipeline Asymmetry** — PROJECT_MAP.md has fallback creation logic, ARCHITECTURE.md does not

**Proposed Fix #3 (line 245):**
> Add ARCHITECTURE.md Fallback to Phase 1: "If absent, flag for creation in Phase 2"

**Alignment:** This analysis confirms and extends the web root cause finding.

---

### From ROOT_CAUSE_MOBILE.md

**Root Cause #3 (line 177):**
> **Pipeline Asymmetry** — PROJECT_MAP.md: "If absent, create it in Phase 7" ✅  
> ARCHITECTURE.md: No fallback creation logic ❌

**Proposed Fix #4 (line 480):**
> Add ARCHITECTURE.md Fallback to Phase 1: "If absent, flag for creation in Phase 2 (bootstrap will run automatically with variant selection for mobile projects)"

**Alignment:** Mobile analysis includes variant selection complexity; this analysis provides the detection foundation variant selection builds upon.

---

## Conclusion

**Root Cause:** Pipeline Phase 1 fails to gracefully handle new projects because:

1. ✅ **Silent failure mode** — missing ARCHITECTURE.md doesn't trigger any action
2. ✅ **Asymmetric fallback** — PROJECT_MAP.md has creation logic, ARCHITECTURE.md doesn't
3. ✅ **No new-project detection** — cannot distinguish new from broken projects
4. ✅ **Optimistic reporting** — assumes success case only
5. ✅ **Guiding Principles gap** — ARCHITECTURE.md not elevated to same status as PROJECT_MAP.md

**Proposed Solution:** 

1. Add new-project detection to Phase 1 (presence/absence of both context files)
2. Report actual state (new/partial/full context) instead of optimistic assumption
3. Add Phase 1.5 bootstrap hook OR extend Phase 2 with bootstrap trigger
4. Elevate ARCHITECTURE.md in Guiding Principles to match PROJECT_MAP.md
5. Update reporting templates to cover all states

**Confidence:** HIGH
- Asymmetry with PROJECT_MAP.md is clear and documented
- New-project detection is straightforward (both files missing)
- Bootstrap trigger aligns with existing Phase 2 stack detection
- Fixes are additive (no breaking changes to existing behavior)

**Integration with Web/Mobile Fixes:**
- Phase 1 DETECTS new projects (this analysis)
- Phase 2 BOOTSTRAPS architecture (web/mobile root cause fixes)
- Together: complete new-project flow

**Next Steps:**
1. Implement Phase 1 new-project detection (highest priority — gates Phase 2 bootstrap)
2. Implement Phase 1 reporting updates (communicates state clearly)
3. Coordinate with subtask-3-3 (Phase 2 bootstrap implementation)
4. Validate across all stacks (Next.js, React, Vue, iOS, Android, KMP)

---

## Appendix: Current vs Proposed Phase 1 Behavior

### Current Behavior (Undefined Missing-File Handling)

```
Phase 1 — Context Load

Check PROJECT_MAP.md → not found (silent)
Check ARCHITECTURE.md → not found (silent)
Check specs/ → not found (silent)
Report: "No context loaded."

→ Proceed to Phase 2 (no signal that this is a new project)
```

### Proposed Behavior (Explicit New-Project Detection)

```
Phase 1 — Context Load

Check PROJECT_MAP.md → not found
Check ARCHITECTURE.md → not found
Detect: Both missing = NEW PROJECT
Flag: Architecture bootstrap required
Report: "New project detected. Bootstrap will run in Phase 1.5/2."

→ Trigger Phase 1.5 bootstrap (or Phase 2 bootstrap section)
→ ARCHITECTURE.md created before Phase 2 discovery
→ Phase 2+ proceed with full context
```

**Key Difference:** Proposed behavior **interprets** the missing-file state instead of silently passing it downstream.
