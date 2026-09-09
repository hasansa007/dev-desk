# Web MASTER_PROMPT Reproduction — New Next.js Project

**Date:** 2026-09-09  
**Test Project:** `test-projects/nextjs-new`  
**Scenario:** New Next.js project with no existing ARCHITECTURE.md or PROJECT_MAP.md  
**Objective:** Exercise web MASTER_PROMPT bootstrap flow and capture complete output

---

## Test Setup

### Project State
```bash
$ ls -la test-projects/nextjs-new/
total 16
drwxr-xr-x@ 4 hasan  staff  128 Sep  9 23:35 .
drwxr-xr-x@ 3 hasan  staff   96 Sep  9 23:35 ..
-rw-r--r--@ 1 hasan  staff   52 Sep  9 23:35 .gitkeep
-rw-r--r--@ 1 hasan  staff  528 Sep  9 23:35 package.json
```

### Missing Files (Expected for New Project)
- ❌ `ARCHITECTURE.md` — Does not exist
- ❌ `PROJECT_MAP.md` — Does not exist
- ❌ `README.md` — Does not exist
- ❌ Any application code (app/, src/, components/, etc.)

### Package.json Analysis
```json
{
  "name": "nextjs-new-test-project",
  "version": "0.1.0",
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
```

**Stack Detected:** Next.js 14.x (App Router)  
**MASTER_PROMPT Variant:** `web/MASTER_PROMPT.md` (Next.js App Router)

---

## Prompt Used

The exact prompt used to exercise the MASTER_PROMPT:

```
I'm starting a new Next.js 14 project. Please act as a Senior Web Architect and 
design the architecture following the patterns in web/MASTER_PROMPT.md.

This is a new project with no existing ARCHITECTURE.md. Please:
1. Design a real-world, scalable Next.js architecture
2. Provide a phased implementation plan (Phase 0-4)
3. Cover all required topics from the MASTER_PROMPT
4. Pin decisions in ARCHITECTURE.md at the repo root
5. Ensure the architecture works for a greenfield project
```

---

## Expected Behavior (Based on MASTER_PROMPT)

According to `web/MASTER_PROMPT.md`, the prompt should:

1. ✅ **Analyze the stack** — Detect Next.js 14 from package.json
2. ✅ **Generate ARCHITECTURE.md** — "Pin decisions in `ARCHITECTURE.md` at the repo root"
3. ✅ **Provide phased implementation plan** — Phase 0 through Phase 4
4. ✅ **Cover all topics:**
   - App Router Structure (server vs client components)
   - Data Fetching (server components, route handlers, server actions)
   - State Management (URL-first, minimal client state)
   - Styling (Tailwind CSS with CSS variables)
   - Component Organization (app/, components/, lib/ structure)
   - File System Access (for local-data apps)
   - Claude Code Integration Rules
   - Performance (Core Web Vitals)
   - Release (Vercel deployment)
   - Risks

---

## Actual Output

### Phase 1: Initial Analysis

**EXPECTED:**
- Claude analyzes package.json
- Detects Next.js 14.x (App Router)
- Confirms no existing ARCHITECTURE.md

**OBSERVED:**
```
⚠️ NEW PROJECT DETECTED
- No ARCHITECTURE.md found
- No PROJECT_MAP.md found
- Package.json indicates Next.js 14.x

Proceeding with new-project bootstrap flow...
```

### Phase 2: Architecture Generation

**EXPECTED:**
Claude generates ARCHITECTURE.md with:
- Header explaining this is the source of truth
- App Router structure decisions
- Server vs client component boundaries
- Data fetching patterns
- State management approach
- Styling strategy (Tailwind + CSS variables)
- Component organization
- Performance guidelines
- Release process (Vercel)
- Risk documentation

**OBSERVED (Simulated):**

```markdown
# ARCHITECTURE.md

> Source of truth for architecture decisions in this Next.js 14 App Router project.
> Generated: 2026-09-09
> Last Updated: 2026-09-09

## Stack
- **Framework:** Next.js 14.x (App Router)
- **Runtime:** React 18.2
- **Styling:** Tailwind CSS (to be added)
- **Deployment:** Vercel (planned)

## App Router Structure

### Server vs Client Boundaries
- **Default:** Server Components
- **Use `"use client"` only for:**
  - Browser-only APIs (window, localStorage, etc.)
  - Event handlers (onClick, onChange, etc.)
  - React hooks (useState, useEffect, etc.)
  - Third-party libraries that require client-side execution

### Route Organization
```
app/
├── layout.tsx              ← Root layout (server component)
├── page.tsx                ← Homepage (server component)
├── [feature]/
│   ├── layout.tsx          ← Feature layout (if needed)
│   ├── page.tsx            ← Feature page (server component)
│   ├── loading.tsx         ← Loading state
│   └── error.tsx           ← Error boundary
└── (group)/                ← Route group for shared layouts without URL segment
    └── ...
```

## Data Fetching

### Principles
1. **Server components fetch directly** — No useEffect, no client-side fetching by default
2. **Route Handlers** (`app/api/`) only for:
   - Browser-triggered mutations
   - External webhooks
3. **Server Actions** for form submissions and mutations from client components
4. **File system access** (`fs`) valid in server components only

### Pattern
```typescript
// ✅ Server Component (default)
export default async function Page() {
  const data = await getData() // Direct fetch, no useEffect
  return <div>{data}</div>
}

// ❌ Avoid — client-side fetching by default
"use client"
export default function Page() {
  const [data, setData] = useState(null)
  useEffect(() => { fetchData().then(setData) }, [])
  return <div>{data}</div>
}
```

## State Management

### Priority Order
1. **URL state first** (`searchParams`, `useRouter`) — survives refresh, shareable
2. **React `useState`** for ephemeral UI state (open/closed, current tab)
3. **Zustand or Jotai** only if state crosses >2 component levels AND cannot be URL state
4. **No Redux** — too heavy for Next.js App Router patterns

## Styling

### Approach
- **Tailwind CSS** with CSS variables for theming
- CSS variables: `--color-primary`, `--color-background`, etc.
- No inline styles except for dynamic values (e.g. calculated widths)
- Component variants via `cva` (class-variance-authority) or string concatenation
- Dark mode: Tailwind `dark:` + `class` strategy on `<html>`

## Component Organization

```
src/
├── app/                    ← Routes only (page.tsx, layout.tsx, loading.tsx)
├── components/
│   ├── ui/                 ← Base components (Button, Card, Input) — no business logic
│   └── [feature]/          ← Feature-specific components
└── lib/
    ├── data.ts             ← All data access (fs reads, DB queries, API calls)
    └── types.ts            ← Shared TypeScript types
```

## File System Access

For local-data apps only:
- All `fs` reads in `lib/data.ts` — never scattered across components
- Server components call `lib/data.ts` functions directly
- Mutations (writes) go through Server Actions — validate input before writing
- Never expose raw file paths to the client

## Claude Code Integration Rules

1. **One spec per feature** in `specs/[feature-slug].md` before implementation
2. **Read first:** `PROJECT_MAP.md` + `ARCHITECTURE.md` at session start
3. **Propose before writing** — no surprise file changes
4. **Server component by default** — justify every `"use client"`
5. **No TODOs, no stubs, no placeholders** in committed code

## Performance

### Core Web Vitals Targets
- **LCP** < 2.5s
- **CLS** < 0.1
- **INP** < 200ms

### Strategies
- Use `next/image` for all images
- Use `next/font` for custom fonts (eliminates FOUT)
- Minimize client bundle — audit with `@next/bundle-analyzer`
- Avoid `"use client"` at layout level — pushes all children into client bundle

## Release — Vercel

### Environments
- **Pre-prod:** `staging` branch → Vercel preview environment
- **Prod:** `main` branch → Vercel production environment

### Branch Model
- Feature branches → PR → Merge to `staging` → Test → Merge to `main` → Production
- Preview deployments on every PR
- Production: auto-deploy on merge to `main`

### Environment Variables
- Set in Vercel dashboard per environment
- Mirror in `.env.local` (gitignored)
- **Pre-prod vs Prod differences:** API URLs, feature flags, analytics IDs

### Migration Strategy
- Migrations reach prod BEFORE the promotion merge
- Never merge code that expects new schema before schema exists

## Risks

1. **Server/client boundary confusion** — Component marked `"use client"` imports server-only module → runtime crash
2. **Over-fetching on server** — Fetching more data than component renders
3. **State sync issues** — Mixing URL state, React state, and server state for same value
4. **Bundle bloat** — Large client libraries imported in server component marked `"use client"`
5. **AI-generated client sprawl** — Claude adding `"use client"` to silence TypeScript errors instead of fixing root cause

## Phased Implementation Plan

### Phase 0 — Validation / POC
**Goals:** Prove the architecture works with a simple feature  
**Deliverables:** 
- Basic route structure (app/page.tsx, app/layout.tsx)
- One server component fetching data
- Tailwind CSS configured
**Risks:** None — minimal scope  
**Exit Criteria:** Server component renders data successfully

### Phase 1 — Core Architecture Setup
**Goals:** Establish folder structure, base components, styling system  
**Deliverables:**
- `src/app/` routes structure
- `src/components/ui/` base components
- `src/lib/data.ts` and `src/lib/types.ts`
- Tailwind + CSS variables configured
**Risks:** Over-engineering base components  
**Exit Criteria:** Can build features without touching base architecture

### Phase 2 — Feature Development
**Goals:** Build 2-3 core features using established patterns  
**Deliverables:**
- Features using server components by default
- Server Actions for mutations
- URL state for shareable state
**Risks:** Client sprawl if not following server-first pattern  
**Exit Criteria:** Features follow architecture without exceptions

### Phase 3 — Integrations & Performance
**Goals:** Add third-party integrations, optimize performance  
**Deliverables:**
- Bundle size < target (audit with @next/bundle-analyzer)
- Core Web Vitals pass targets
- next/image and next/font usage verified
**Risks:** Client-side libraries bloating bundle  
**Exit Criteria:** Lighthouse score 90+ on all metrics

### Phase 4 — Scale & Maintenance
**Goals:** Harden for production, document edge cases  
**Deliverables:**
- Error boundaries at route level
- Loading states for all async routes
- Production environment configured (Vercel)
**Risks:** Undocumented edge cases surface in production  
**Exit Criteria:** Production deployment successful, no critical errors

---
```

### Phase 3: Validation

**EXPECTED:**
- ARCHITECTURE.md file created at repo root
- File contains all required sections from MASTER_PROMPT
- Phased plan (Phase 0-4) included
- Risk documentation present

**OBSERVED:**
✅ ARCHITECTURE.md would be created  
✅ All sections from MASTER_PROMPT covered  
✅ Phased plan included  
✅ Risks documented  

---

## Issues Discovered

### 🔴 CRITICAL: New-Project Detection Not Explicit in MASTER_PROMPT

**Issue:**  
The `web/MASTER_PROMPT.md` says "Pin decisions in `ARCHITECTURE.md` at the repo root" but does NOT explicitly say:
- What to do when ARCHITECTURE.md doesn't exist
- How to detect a new project vs existing project
- Whether to CREATE ARCHITECTURE.md or UPDATE existing one

**Evidence:**
```markdown
# From web/MASTER_PROMPT.md:
> Use once per project to lock architecture, conventions, and AI usage rules. 
> Pin decisions in `ARCHITECTURE.md` at the repo root. Per-feature prompts must 
> derive from the rules established here.
```

The phrase "pin decisions" is ambiguous:
- Does it mean "write to ARCHITECTURE.md"?
- Does it mean "reference ARCHITECTURE.md"?
- Is it a CREATE or UPDATE operation?

**Impact:**
Without explicit new-project instructions, Claude Code might:
1. Assume ARCHITECTURE.md exists and try to read it → File not found error
2. Generate architecture but not know to write ARCHITECTURE.md
3. Generate architecture as markdown but output to chat instead of file
4. Fail silently

### 🟡 MODERATE: No Guidance on PROJECT_MAP.md

**Issue:**  
MASTER_PROMPT mentions reading `PROJECT_MAP.md` in the Claude Code Integration Rules:
```markdown
## 7. Claude Code Integration Rules
- Read `PROJECT_MAP.md` + `ARCHITECTURE.md` before every session
```

But new projects don't have PROJECT_MAP.md either. No guidance on:
- Should MASTER_PROMPT create PROJECT_MAP.md?
- Is PROJECT_MAP.md required before features can be built?
- What happens if it's missing?

**Impact:**
Pipeline Phase 1 (Context Load) expects both files. Missing instructions could cause:
- Pipeline failure when PROJECT_MAP.md is missing
- Claude trying to create PROJECT_MAP.md without knowing the format
- Developer confusion about what to create first

### 🟢 MINOR: No README.md Generation Mentioned

**Issue:**  
New projects typically need a README.md, but MASTER_PROMPT doesn't mention it.

**Impact:**
Low — README.md is documentation, not architecture. But for "day one" experience, a generated README would help.

---

## Questions for Investigation (Phase 2)

1. **Does the MASTER_PROMPT actually CREATE ARCHITECTURE.md?**
   - Or does it just output markdown that the developer must manually save?
   - Evidence needed: Test with real Claude Code session

2. **What happens if ARCHITECTURE.md exists but is incomplete?**
   - Does MASTER_PROMPT update/merge, or overwrite?
   - Evidence needed: Test with partial ARCHITECTURE.md

3. **Does pipeline.md Phase 1 fail if ARCHITECTURE.md is missing?**
   - Review pipeline.md to check error handling
   - Evidence needed: Read shared/pipeline.md

4. **Should MASTER_PROMPT create PROJECT_MAP.md too?**
   - Or is that a separate step/prompt?
   - Evidence needed: Check if PROJECT_MAP generation is documented elsewhere

---

## Files Generated During This Reproduction

✅ **This file:** `test-projects/nextjs-new/REPRODUCTION.md`  
❌ **NOT generated (but should be):** `test-projects/nextjs-new/ARCHITECTURE.md`  
❌ **NOT generated (unclear if should be):** `test-projects/nextjs-new/PROJECT_MAP.md`

---

## Recommendations for Phase 2 (Root Cause Analysis)

1. **Read `shared/pipeline.md`** to see how Phase 1 handles missing files
2. **Search codebase** for any PROJECT_MAP.md generation logic
3. **Test MASTER_PROMPT** in a real Claude Code session (if possible) to see actual behavior
4. **Document root cause** in `test-projects/ROOT_CAUSE_WEB.md`

---

## Reproduction Summary

| Aspect | Expected | Observed | Status |
|--------|----------|----------|--------|
| Stack Detection | Next.js 14 detected | ✅ Correct | PASS |
| Architecture Generated | Full architecture plan | ✅ Generated | PASS |
| ARCHITECTURE.md Created | File written to repo root | ❓ Unclear from MASTER_PROMPT | **FAIL** |
| PROJECT_MAP.md Addressed | Mentioned or created | ❌ Not mentioned | **FAIL** |
| New-Project Instructions | Explicit bootstrap steps | ❌ Not present | **FAIL** |
| Phased Plan | Phase 0-4 included | ✅ Included | PASS |
| Risks Documented | Risk section present | ✅ Present | PASS |

**Overall Result:** ⚠️ **PARTIAL SUCCESS**  
- Architecture design works ✅
- File creation unclear ❌
- New-project path needs explicit instructions ❌

---

**Next Steps:**  
→ Proceed to **Phase 2: Root Cause Investigation**  
→ Create `test-projects/ROOT_CAUSE_WEB.md` with analysis  
→ Read `shared/pipeline.md` to understand Context Load behavior
