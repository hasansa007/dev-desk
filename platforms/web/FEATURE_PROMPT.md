# Feature Prompt — Web (Next.js App Router)

> Use this section for every new feature in a Next.js App Router project.
> Detect stack from Phase 2. Skip if project uses a different web framework.

---

## Header (always)

```
# Feature Prompt: [Feature Name]

Implement the feature: [describe feature clearly]

## Product Behavior
[Explain what the user should see/do — walk through the user journey step by step]

## Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] [Criterion 3]
```

---

## Web Scope (Next.js App Router)

```
## Component Boundary Decision
- Server component (default) OR Client component — justify if client
- If client: what user interaction requires it? (event handlers, browser APIs, real-time state)

## Route Structure
- New route: app/[path]/page.tsx
- Uses existing layout: app/[path]/layout.tsx (if applicable)
- Loading state: app/[path]/loading.tsx (if async data)

## Data Source
- File system (lib/data.ts + fs) / Route Handler / Server Action / External API
- What data is read? What data is written?

## Components to Create / Modify
- [ComponentName] — server/client — purpose
- [ComponentName] — server/client — purpose

## State
- URL state / React state / none — describe what and why

## Claude Code Instructions
1. Read PROJECT_MAP.md + ARCHITECTURE.md before starting
2. Read all files you plan to touch before editing
3. Server component by default — add "use client" only with explicit justification
4. Match existing naming, folder, and import conventions
5. No TODOs, stubs, or placeholder implementations
6. Handle real error cases — no silent failures

## Output Required
- Files created / modified (with paths)
- Server/client boundary decision explained for each component
- Any new lib/data.ts functions added
- Manual QA checklist
- Known risks or edge cases
```
