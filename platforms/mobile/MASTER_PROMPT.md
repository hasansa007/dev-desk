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

## New Project Bootstrap

### When to use this section
Use when starting a **new mobile project from scratch**. Skip if joining an existing project with established architecture.

### Detection
Run Phase 2 detection from `shared/pipeline.md` to identify the variant. If no project exists yet, choose based on requirements:
- iOS target only → **Variant A**
- Android target only → **Variant B**
- Both iOS + Android with shared business logic → **Variant C**

### Common Bootstrap Steps (all variants)

Before variant-specific setup:

1. **Create project context files:**
   - `PROJECT_MAP.md` — tech stack, system flow, orphans tracking
   - `ARCHITECTURE.md` — architectural decisions, conventions, module boundaries
   - `.claude/` directory — Claude Code integration rules

2. **Pin architecture rules:**
   - Create `/tools/claude-prompts/ARCHITECTURE_RULES.md` OR `.claude/rules/architecture.md`
   - Extract decisions from this MASTER_PROMPT run into persistent rules
   - Include: module boundaries, naming conventions, forbidden patterns, DI approach

3. **Set up feature spec directory:**
   - `specs/` or `/docs/features/` — one markdown file per feature
   - Template: goal, acceptance criteria, contracts, native integration points

4. **Initialize version control:**
   - `.gitignore` — platform-specific (iOS: `.xcodeproj/xcuserdata`, Android: `build/`, `*.iml`)
   - Branch strategy — `main` (stable) + `develop` + feature branches
   - PR template — includes architecture checklist, native integration verification

5. **CI/CD foundation:**
   - GitHub Actions / Bitrise / Fastlane setup
   - Build verification, test runs, code review automation

---

### Variant A Bootstrap — iOS only (Swift / SwiftUI)

#### Initial project structure
```
MyApp/
├── MyApp.xcodeproj
├── MyApp/
│   ├── App/
│   │   └── MyAppApp.swift            # App entry point
│   ├── Core/
│   │   ├── DI/                       # Dependency injection
│   │   ├── Data/                     # SwiftData / Core Data models
│   │   └── Utilities/                # Shared utilities
│   ├── Features/
│   │   └── [FeatureName]/            # One directory per feature
│   │       ├── Views/
│   │       ├── ViewModels/
│   │       └── Models/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── Packages/                          # Local Swift packages (optional)
├── specs/                             # Feature specifications
├── PROJECT_MAP.md
├── ARCHITECTURE.md
└── .claude/
    └── rules/
        └── architecture.md
```

#### Bootstrap checklist
1. **Create Xcode project** with SwiftUI lifecycle
2. **Set up Swift Package dependencies:**
   - Local packages per feature (if modularizing from day 1)
   - External: networking, logging, analytics
3. **Define core architecture:**
   - `@Observable` view models pattern
   - Navigation approach (NavigationStack, coordinators, or TCA-style)
   - DI strategy (environment objects, factory pattern, or @EnvironmentKey)
4. **Establish data layer:**
   - SwiftData (iOS 17+) OR Core Data OR GRDB
   - Repository pattern for data access
   - Sync orchestration approach (if needed)
5. **Set up native integrations skeleton:**
   - HealthKit entitlements + `HealthKitManager` stub
   - Background task registration + `BackgroundTaskManager` stub
   - Push notifications entitlements + `NotificationManager` stub
6. **Create first feature via Claude Code:**
   - Write spec: `specs/onboarding.md`
   - Generate contracts first (view model protocol, repository protocol)
   - Let Claude scaffold views + view models
   - Manually integrate native permissions flow
7. **Pin architecture decisions in `ARCHITECTURE.md`:**
   - Navigation: "NavigationStack with enum-based routes"
   - State: "@Observable view models, no Combine/async subscriptions in views"
   - Data: "SwiftData with repository pattern, sync via BackgroundTasks"
   - Testing: "ViewInspector for views, in-memory repos for view model tests"

#### Claude Code integration
- **Prompt template location:** `.claude/prompts/feature-scaffold-ios.md`
- **Checklist for AI reviews:** `.claude/checklists/ios-code-review.md`
- **Forbidden patterns:** document in `ARCHITECTURE.md` (e.g. "No `@StateObject`, use `@State` with `@Observable`")

---

### Variant B Bootstrap — Android only (Kotlin / Jetpack Compose)

#### Initial project structure
```
MyApp/
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/com/myapp/
│       │   ├── MyApplication.kt      # App entry point
│       │   ├── MainActivity.kt       # Compose entry
│       │   └── navigation/           # Nav graph
│       └── res/
├── core/
│   ├── data/                          # Room, DataStore, repos
│   ├── domain/                        # Use cases, models
│   ├── common/                        # Utilities, DI
│   └── ui/                            # Design system, theme
├── feature/
│   └── [feature-name]/                # One module per feature
│       ├── build.gradle.kts
│       └── src/main/kotlin/
│           ├── [FeatureName]Screen.kt
│           ├── [FeatureName]ViewModel.kt
│           └── [FeatureName]Repository.kt
├── build.gradle.kts                   # Root build config
├── settings.gradle.kts                # Module inclusion
├── specs/
├── PROJECT_MAP.md
├── ARCHITECTURE.md
└── .claude/
    └── rules/
        └── architecture.md
```

#### Bootstrap checklist
1. **Create Android project** with Jetpack Compose + Material3
2. **Set up multi-module structure:**
   - `:app` — main entry point
   - `:core:data`, `:core:domain`, `:core:common`, `:core:ui`
   - `:feature:[name]` modules (add as needed)
3. **Configure Gradle dependencies:**
   - Compose BOM, ViewModel, Navigation
   - Room / SQLDelight, DataStore
   - Hilt / Koin for DI
   - WorkManager for background tasks
4. **Define core architecture:**
   - MVVM with ViewModel + UI state
   - Repository pattern for data access
   - Navigation graph with type-safe routes
5. **Establish data layer:**
   - Room entities + DAOs
   - Repository interfaces in `:core:domain`
   - Implementations in `:core:data`
6. **Set up native integrations skeleton:**
   - Health Connect permissions + `HealthConnectManager` stub
   - WorkManager periodic tasks + `SyncWorker` stub
   - Foreground service for real-time tracking (if needed)
7. **Create first feature via Claude Code:**
   - Write spec: `specs/onboarding.md`
   - Generate contracts first (ViewModel, Repository interfaces)
   - Let Claude scaffold Compose UI + ViewModel
   - Manually integrate permissions flow
8. **Pin architecture decisions in `ARCHITECTURE.md`:**
   - Navigation: "Type-safe Compose Navigation with sealed class routes"
   - State: "ViewModel with StateFlow, UI layer collects as State"
   - Data: "Room + Repository pattern, WorkManager for sync"
   - DI: "Hilt, one module per layer"
   - Testing: "Compose test rules, fake repos, Turbine for flows"

#### Claude Code integration
- **Prompt template location:** `.claude/prompts/feature-scaffold-android.md`
- **Checklist for AI reviews:** `.claude/checklists/android-code-review.md`
- **Forbidden patterns:** document in `ARCHITECTURE.md` (e.g. "No `GlobalScope.launch`, use `viewModelScope`")

---

### Variant C Bootstrap — iOS + Android + KMP

#### Initial project structure
```
MyApp/
├── androidApp/                        # Android native
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       └── kotlin/com/myapp/
│           ├── MyApplication.kt
│           ├── MainActivity.kt
│           └── ui/                    # Compose UI
│               └── [Feature]Screen.kt
├── iOSApp/                            # iOS native
│   ├── iOSApp.xcodeproj
│   └── iOSApp/
│       ├── MyApp.swift
│       ├── Features/
│       │   └── [Feature]/
│       │       ├── [Feature]View.swift
│       │       └── [Feature]ViewModel.swift  # Wraps KMP)
│       └── NativeAdapters/            # Bridge to KMP
├── shared/                            # KMP shared code
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/
│       │   ├── domain/                # Business logic
│       │   │   ├── models/            # Data models
│       │   │   ├── usecases/          # Use cases
│       │   │   └── ports/             # Interfaces for native
│       │   ├── data/                  # Repos, API clients
│       │   └── validation/            # Shared validation rules
│       ├── androidMain/kotlin/        # Android-specific shared
│       └── iosMain/kotlin/            # iOS-specific shared
├── specs/                             # SHARED feature specs
├── PROJECT_MAP.md
├── ARCHITECTURE.md
└── .claude/
    └── rules/
        └── architecture.md
```

#### Bootstrap checklist
1. **Create KMP project** via KMP wizard or template
2. **Define KMP boundaries FIRST** (critical for preventing drift):
   - **Shared (KMP):** domain models, validation, API contracts, sync orchestration, business rules
   - **Native (platform-specific):** UI, navigation, permissions, HealthKit/Health Connect, background tasks, real-time updates
3. **Set up shared module:**
   - `expect`/`actual` for platform-specific implementations
   - Ports (interfaces) for native adapters: `HealthDataPort`, `BackgroundSyncPort`, `PermissionsPort`
   - SQLDelight for shared database (if cross-platform DB needed)
4. **Set up iOS native layer:**
   - Swift view models wrapping KMP use cases
   - Native adapters implementing KMP ports: `HealthKitAdapter: HealthDataPort`
   - SwiftUI views consuming Swift view models
5. **Set up Android native layer:**
   - Compose UI + ViewModel wrapping KMP use cases
   - Native adapters implementing KMP ports: `HealthConnectAdapter: HealthDataPort`
   - Hilt modules providing platform-specific implementations
6. **Establish parity validation:**
   - Shared acceptance criteria in `specs/[feature].md`
   - Cross-platform integration tests
   - Manual QA checklist for both platforms
7. **Create first feature via Claude Code (COORDINATED):**
   - Write ONE spec: `specs/onboarding.md` with shared + platform-specific sections
   - Generate KMP contracts first (use cases, ports, models)
   - Generate iOS + Android scaffolds FROM THE SAME SPEC
   - Manually integrate native adapters on each platform
8. **Pin architecture decisions in `ARCHITECTURE.md`:**
   - KMP boundaries: "Domain + data in shared, UI + device integrations native"
   - Bridge pattern: "Native adapters implement KMP ports, passed via DI"
   - Parity: "Shared specs, shared acceptance tests, platform-specific integration tests"
   - Testing: "KMP unit tests for domain, native tests for UI + integrations"

#### Claude Code integration (CRITICAL for parity)
- **Single spec per feature:** `.claude/prompts/feature-scaffold-kmp.md` generates for BOTH platforms
- **Shared checklist:** `.claude/checklists/kmp-code-review.md` includes parity verification
- **Forbidden patterns:** 
  - "No platform-specific logic in `commonMain`"
  - "No business logic in native layers"
  - "No independent AI generation per platform without shared spec"

#### Parity safeguards
1. **Shared feature specs** — one source of truth for both platforms
2. **Parity validation step** — compare iOS + Android implementations against shared acceptance criteria
3. **CI parity tests** — automated checks that both platforms implement the same contracts
4. **Code review checklist** — explicit parity verification before merge

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
