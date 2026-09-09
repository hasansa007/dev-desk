# Feature Prompt: System Status Dashboard

Implement the feature: System Status and Health Metrics Dashboard

## Product Behavior
A user navigates to `/status` to inspect the real-time operational health, uptime, database connectivity status, and environment version of the application. The page displays a high-level status banner (Operational / Degraded / Down) and a breakdown of subsystem checks.

## Acceptance Criteria
- [ ] Route `/status` renders server-side with zero client-side hydration errors
- [ ] Subsystem health metrics (API Gateway, Database, Storage, Cache) are displayed with status badges
- [ ] Data is read through `src/lib/data.ts` without direct inline DB/API logic in page component
- [ ] Visual styling matches Tailwind theme with support for dark mode

---

## Web Scope (Next.js App Router)

## Component Boundary Decision
- `app/status/page.tsx` — Server Component (fetches system metrics directly on server)
- `components/ui/card.tsx` — Server Component (pure markup layout)
- `components/ui/badge.tsx` — Server Component (pure markup styling)
- `components/status/status-view.tsx` — Server Component (presents health telemetry)

## Route Structure
- New route: `src/app/status/page.tsx`
- Loading state: `src/app/status/loading.tsx`

## Data Source
- File/Service access in `src/lib/data.ts` (`getSystemStatus()`)
- Read operations only; returns typed `SystemStatusReport`

## Components to Create / Modify
- `Card`, `CardHeader`, `CardTitle`, `CardContent` — server — base container UI
- `Badge` — server — status indicator (healthy, degraded, down)
- `StatusView` — server — metrics summary card and check grid

## State
- None required on client; purely server-rendered telemetry

## Claude Code Instructions
1. Read `PROJECT_MAP.md` + `ARCHITECTURE.md` before starting
2. Read all files you plan to touch before editing
3. Server component by default — add "use client" only with explicit justification
4. Match existing naming, folder, and import conventions
5. No TODOs, stubs, or placeholder implementations
6. Handle real error cases — no silent failures

## Output Required
- Files created:
  - `src/lib/types.ts`
  - `src/lib/utils.ts`
  - `src/lib/data.ts`
  - `src/components/ui/card.tsx`
  - `src/components/ui/badge.tsx`
  - `src/components/status/status-view.tsx`
  - `src/app/status/page.tsx`
  - `src/app/status/loading.tsx`
- Server/client boundary decision explained for each component
- Verified against ARCHITECTURE.md conventions
