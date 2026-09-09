# Architecture Strategy — E2E Next.js Project

> Locked architecture, conventions, and AI usage rules pinned at repo root.
> Generated via `web/MASTER_PROMPT.md` for Next.js 14 (App Router).

---

## 1. Goal & Architecture Overview

Design a production-grade, scalable Next.js 14 App Router architecture that:
- Ships features rapidly with minimal cognitive complexity
- Employs React Server Components (RSC) by default; client components only when interactivity is required
- Keeps data flow explicit, typed, and localized to `src/lib/data.ts`
- Treats AI coding agents (Claude Code / Antigravity) as force multipliers with clear constraints

---

## 2. Phased Implementation Plan

- **Phase 0 — Validation / POC**: Baseline app router layout, verify path resolution, base UI components
- **Phase 1 — Core Architecture Setup**: Layouts, styling variables, error/loading boundaries, types
- **Phase 2 — Feature Development**: Feature slices in `src/app/` with direct server component data loading
- **Phase 3 — Integrations & Performance**: Core Web Vitals audit, dynamic metadata, bundle trimming
- **Phase 4 — Scale & Maintenance**: Regression suite, CI verification, documentation updates

---

## 3. App Router Structure

- **Server vs Client Component Boundaries**:
  - Components are Server Components by default.
  - Mark `\"use client\"` ONLY when utilizing browser hooks (`useState`, `useEffect`), DOM listeners (`onClick`, `onChange`), or browser APIs.
  - Never wrap entire pages or root layouts in `\"use client\"`.
- **Route Organization**:
  - `src/app/[feature]/page.tsx` — route view and server-side data fetching
  - `src/app/[feature]/layout.tsx` — persistent UI shell
  - `src/app/[feature]/loading.tsx` — instant skeleton / streaming boundary
  - `src/app/[feature]/error.tsx` — granular fault isolation boundary

---

## 4. Data Fetching & File Access

- **Server Component Fetching**:
  - Server components call data access utilities directly; no client-side `useEffect` data fetching.
- **Data Layer Isolation**:
  - All data access functions live in `src/lib/data.ts`.
  - Direct file system (`fs/promises`) or database operations occur solely within server modules.
  - Client components invoke Server Actions in `src/lib/actions.ts` or API route handlers in `src/app/api/`.

---

## 5. State Management

- **URL State First**:
  - Filter, search, tab, and pagination state live in URL search params (`searchParams`, `useRouter`, `useSearchParams`).
  - Shareable and survives page refreshes.
- **Ephemeral State**:
  - Local component state via React `useState` for modals, dropdown toggles, and draft inputs.
- **Global State**:
  - Avoid Redux. Use Zustand only if cross-component client state cannot be represented in the URL.

---

## 6. Styling & Component Organization

- **Styling**:
  - Tailwind CSS with CSS variables (`--color-primary`, `--color-bg`).
  - Class merging using `clsx` and `tailwind-merge` via `cn()` utility in `src/lib/utils.ts`.
  - Dark mode supported via `.dark` selector on `<html>`.
- **Directory Layout**:
  ```
  src/
  ├── app/                  ← Routes, layouts, and loading/error states
  ├── components/
  │   ├── ui/               ← Base atomic components (Button, Card, Input)
  │   └── [feature]/        ← Feature-specific component trees
  └── lib/
      ├── data.ts           ← Server data access and queries
      ├── utils.ts          ← Formatting and class utilities
      └── types.ts          ← Domain and shared TypeScript interfaces
  ```

---

## 7. Claude Code & Agent Integration Rules

- One spec per feature in `specs/[feature-slug].md` before coding starts.
- Read `PROJECT_MAP.md` + `ARCHITECTURE.md` before every editing session.
- Propose file changes before writing — surgical edits only.
- Default to Server Components; require explicit justification for every `\"use client\"`.
- No TODOs, stubs, or placeholder mocks in committed production code.
- Clean up orphaned imports, types, or unused functions immediately.

---

## 8. Performance & Release Strategy

- **Core Web Vitals**: Target LCP < 2.5s, CLS < 0.1, INP < 200ms.
- **Fonts & Media**: Use `next/font` for web fonts to prevent layout shift; `next/image` for image assets.
- **Bundle Hygiene**: Prevent bloated client bundles; inspect with bundle analyzer.
- **Release Model**:
  - Feature branches merge to `main` via PR.
  - Vercel preview environments per PR for visual QA.
  - Production deployments automated upon merge to `main` with health check verification.

---

## 9. New-Project Bootstrap (Validated)

- **Path Validation**:
  - Always validate target root path with `path.resolve()` before filesystem writes.
  - Never execute file writes based on untrusted relative assumptions or unverified parent paths.
- **Bootstrap Sequence**:
  1. Validate target directory existence and write permissions.
  2. Create core directories in order (`src/app/`, `src/components/ui/`, `src/lib/`).
  3. Initialize build configurations (`next.config.js`, `tailwind.config.js`, `tsconfig.json`).
  4. Pin `ARCHITECTURE.md` at repo root.
  5. Establish `PROJECT_MAP.md` tracking stack, system flows, and pending items.

---

## 10. Architectural Risks & Mitigations

- **Risk: Server/Client boundary leakage** → Enforce `server-only` package in `src/lib/data.ts` to fail builds if imported in client components.
- **Risk: Client bundle bloat** → Keep leaf components client-side; push server data down as props.
- **Risk: Divergent AI coding patterns** → Pin rules in `ARCHITECTURE.md` and check against rules during Phase 9 verification.
