# Project Map — E2E Test Project

## TECH_STACK
- Framework: Next.js 14.2 (App Router)
- Language: TypeScript 5.5
- UI / Styling: Tailwind CSS 3.4, React Server Components (RSC)
- Utilities: clsx, tailwind-merge
- Architecture: Feature-first with centralized data access in `src/lib/data.ts`

## SYSTEM_FLOW
1. Entry: `src/app/page.tsx` renders landing hero linking to `/status`.
2. Telemetry Flow:
   - User navigates to `/status`.
   - `src/app/status/loading.tsx` streams while server resolves.
   - `src/app/status/page.tsx` (Server Component) fetches metrics via `getSystemStatus()` in `src/lib/data.ts`.
   - Metrics rendered into `StatusView` component (`src/components/status/status-view.tsx`) using atomic UI primitives (`Card`, `Badge`).
   - Pure server-side rendering with zero client-side javascript runtime overhead for metrics display.

## ORPHANS & PENDING
- None. All components referenced in routes and data pipelines.
