# Master Prompt — Web Architecture Strategy (Next.js App Router)

> **Use once per project** to lock architecture, conventions, and AI usage rules. Pin decisions in `ARCHITECTURE.md` at the repo root. Per-feature prompts must derive from the rules established here.

Use when `package.json` indicates Next.js (App Router). If the project uses a different web stack, adapt accordingly.

---

## Goal
Design a real-world, scalable Next.js architecture that:
- Ships features fast with minimal complexity
- Uses server components by default — client components only when necessary
- Keeps data flow explicit and ownership clear
- Uses AI (Claude Code) as a force multiplier, not a risk

Act as a **Senior Web Architect** and provide a **phased implementation plan**. Each phase must include **Goals, Deliverables, Risks, Exit Criteria**.

Phases:
- **Phase 0 — Validation / POC**
- **Phase 1 — Core Architecture Setup**
- **Phase 2 — Feature Development**
- **Phase 3 — Integrations & Performance**
- **Phase 4 — Scale & Maintenance**

---

## Topics to Cover

### 1. App Router Structure
- Server vs client component boundaries — when to use `"use client"`
- Route organization: `app/[feature]/page.tsx`, `app/[feature]/layout.tsx`
- Route groups `(group)/` for shared layouts without URL segments
- Loading and error boundaries per route segment

### 2. Data Fetching
- Server components fetch data directly — no useEffect, no client-side fetching by default
- Route Handlers (`app/api/`) only for browser-triggered mutations or external webhooks
- Server Actions for form submissions and mutations from client components
- File system access (`fs`) — valid in server components, never in client components

### 3. State Management
- URL state first (`searchParams`, `useRouter`) — survives refresh, shareable
- React `useState` for ephemeral UI state (open/closed, current tab)
- Zustand or Jotai only if state crosses more than 2 component levels AND cannot be URL state
- No Redux — too heavy for Next.js App Router patterns

### 4. Styling
- Tailwind CSS with CSS variables for theming (`--color-primary`, etc.)
- No inline styles except for dynamic values (e.g. calculated widths)
- Component variants via `cva` (class-variance-authority) or simple string concatenation
- Dark mode via Tailwind `dark:` + `class` strategy on `<html>`

### 5. Component Organization
```
src/
├── app/                    ← routes only (page.tsx, layout.tsx, loading.tsx)
├── components/
│   ├── ui/                 ← base components (Button, Card, Input) — no business logic
│   └── [feature]/          ← feature-specific components
└── lib/
    ├── data.ts             ← all data access (fs reads, DB queries, API calls)
    └── types.ts            ← shared TypeScript types
```

### 6. File System Access (local-data apps)
- All `fs` reads go in `lib/data.ts` — never scatter them across components
- Server components call `lib/data.ts` functions directly
- Mutations (writes) go through Server Actions — validates input before writing
- Never expose raw file paths to the client

### 7. Claude Code Integration Rules
- One spec per feature in `specs/[feature-slug].md` before implementation starts
- Read `PROJECT_MAP.md` + `ARCHITECTURE.md` before every session
- Propose file changes before writing — no surprises
- Server component by default — justify every `"use client"`
- No TODOs, no stubs, no placeholders in committed code

### 8. Performance
- Core Web Vitals: LCP < 2.5s, CLS < 0.1, INP < 200ms
- Use `next/image` for all images
- Use `next/font` for all custom fonts (eliminates FOUT)
- Minimize client bundle: audit with `@next/bundle-analyzer`
- Avoid `"use client"` at layout level — pushes all children into client bundle

### 9. Deployment (Vercel)
- Environment variables in Vercel dashboard, mirrored in `.env.local` (gitignored)
- Preview deployments on every PR — use for testing before merge
- `vercel --prod` or push to main for production deploy

### 10. Risks
- **Server/client boundary confusion** — component marked `"use client"` that imports a server-only module (crashes at runtime)
- **Over-fetching on server** — fetching more data than the component renders
- **State sync issues** — mixing URL state, React state, and server state for the same value
- **Bundle bloat** — large client-side libraries imported in a server component that got marked `"use client"`
- **AI-generated client sprawl** — Claude adding `"use client"` to silence TypeScript errors instead of fixing the real issue
