# Master Prompt — Mobile Architecture Strategy

> **Conditional use.** Pick the variant that matches the project. If the stack does not match any variant below, **do not use this prompt**.

Use **once per project** to lock architecture, conventions, and AI usage rules. Pin the resulting decisions in the repo (e.g. `ARCHITECTURE.md`, `/specs/`, `/tools/claude-prompts/ARCHITECTURE_RULES.md`). Per-feature prompts must derive from the rules established here.

Detect stack from Phase 2 of the pipeline:
- `*.xcodeproj` / `Package.swift` (Swift) only → **Variant A — iOS-only**
- `build.gradle*` + Android manifest only → **Variant B — Android-only**
- `androidApp/` + `iOSApp/` + `shared/` (KMP) → **Variant C — iOS + Android + KMP**

---

## Shared Goal (all variants)
Design a real-world, scalable architecture and execution model that:
- Ships features fast
- Maximizes native platform capabilities
- Uses AI (Claude Code) as a force multiplier, not a risk
- Keeps complexity visible and ownership clear

Act as a **Senior Mobile Architect** and provide a **deep, phased implementation plan**. Each phase must include **Goals, Deliverables, Risks, Exit Criteria**.

Phases:
- **Phase 0 — Validation / POC**
- **Phase 1 — Core Architecture Setup**
- **Phase 2 — Feature Development**
- **Phase 3 — Native Integrations**
- **Phase 4 — Optimization & Scale**

Deliverables:
- Architecture diagram (text or Mermaid)
- Feature development lifecycle
- Practical workflow (battle-tested, not theoretical)

---

## Variant A — iOS only (Swift / SwiftUI)

### Context
Native iOS app. Heavy use of Claude Code for scaffolding, refactoring, consistency.
Strong need to preserve native platform power: SwiftUI, Apple Watch, HealthKit, BackgroundTasks, WidgetKit.

### Topics to cover
1. **Feature-first modularization** — Swift packages per feature, clear module graph.
2. **Architecture** — SwiftUI + `@Observable` view models, navigation patterns, DI.
3. **Native integrations** — HealthKit, Apple Watch / WatchConnectivity, BGTasks, Widgets, Push.
4. **Data & sync** — local-first (SwiftData / Core Data / GRDB), sync orchestration, conflict resolution.
5. **Claude Code integration** — one spec per feature, architecture rules pinned in prompts, code review checklist.
6. **Workflow** — spec → contracts → AI scaffold → integrations → QA. Branching, review, CI/CD.
7. **Performance** — main-thread budget, Instruments-driven profiling.
8. **Scaling** — adding features, onboarding, long-term consistency.
9. **Risks** — AI hallucinations, hidden complexity, untested device paths.

---

## Variant B — Android only (Kotlin / Jetpack Compose)

### Context
Native Android app. Heavy use of Claude Code for scaffolding, refactoring, consistency.
Strong need to preserve native power: Compose, Health Connect / Google Fit, WorkManager, Services, Widgets.

### Topics to cover
1. **Feature-first modularization** — Gradle module per feature, clear `:core` / `:feature:*` graph.
2. **Architecture** — Compose + Jetpack ViewModel, navigation, DI (Hilt/Koin).
3. **Native integrations** — Health Connect / Google Fit, WorkManager, foreground services, Widgets, Push.
4. **Data & sync** — local-first (Room / SQLDelight / DataStore), sync orchestration, conflict resolution.
5. **Claude Code integration** — one spec per feature, architecture rules pinned, code review checklist.
6. **Workflow** — spec → contracts → AI scaffold → integrations → QA. Branching, review, CI/CD.
7. **Performance** — Macrobenchmark, Perfetto, baseline profiles.
8. **Scaling** — adding features, onboarding, long-term consistency.
9. **Risks** — AI hallucinations, hidden complexity, background-execution gotchas.

---

## Variant C — iOS + Android + KMP

### Context
Feature-based **parallel development**: iOS and Android teams work simultaneously on the same features, sharing logic via Kotlin Multiplatform.
Tech: Swift/SwiftUI, Kotlin/Jetpack, KMP, Claude Code.
Strong need to preserve native power on both sides (Apple Watch + HealthKit, Google Fit / Health Connect, background, real-time, animations).

### Topics to cover (in addition to the shared goal)
1. **Parallel feature development** — feature squads (not platform silos), ownership, drift prevention.
2. **Architecture (feature-first)** — vertical slices; Shared (KMP) = domain, models, validation, API contracts, sync; Native = UI, navigation, permissions, device integrations. Strict KMP boundaries.
3. **Native integration strategy** — Apple Watch + HealthKit; Google Fit / Health Connect; permissions; background sync; real-time updates. Bridging pattern: **Native Adapter → KMP Port**.
4. **Data & sync** — local-first; high-frequency data (steps, calories, workouts); orchestration & conflict resolution; data ownership (shared vs platform-specific).
5. **Claude Code integration** — one shared feature spec; shared acceptance criteria; architecture rules pinned in prompts; AI code review checklist; **no independent generation per platform**.
6. **Workflow** — spec → shared contracts → AI scaffold (layer by layer) → native integrations → parity validation → QA. Branching, review, CI/CD with parity tests.
7. **Performance** — what stays native; KMP overhead risks; profiling on both platforms.
8. **Scaling** — feature addition, onboarding, long-term consistency.
9. **Critical risks** — over-reliance on KMP; AI-generated divergence; feature desync; hidden complexity in shared layers.

### Final instruction (Variant C)
Design with a **strong bias toward native platform quality**, using KMP only where it clearly reduces duplication without introducing complexity, limitations, or platform drift.
