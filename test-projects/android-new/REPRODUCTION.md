# Mobile MASTER_PROMPT Reproduction — Android (Variant B)

**Date:** 2026-09-09  
**Test Project:** `test-projects/android-new/`  
**Variant:** B — Android only (Kotlin / Jetpack Compose)  
**Stack Detected:** `build.gradle` present, Android manifest expected

---

## Input Context

The MASTER_PROMPT was invoked with the following context:
- **Stack:** Native Android app
- **Tech:** Kotlin, Jetpack Compose
- **AI Tool:** Claude Code for scaffolding, refactoring, consistency
- **Native Power Requirements:** Compose, Health Connect / Google Fit, WorkManager, Services, Widgets

---

## Prompt Used (Variant B)

```
Act as a Senior Mobile Architect and provide a deep, phased implementation plan for a new Android app.

Context:
Native Android app. Heavy use of Claude Code for scaffolding, refactoring, consistency.
Strong need to preserve native power: Compose, Health Connect / Google Fit, WorkManager, Services, Widgets.

Provide a phased implementation plan covering:

1. **Feature-first modularization** — Gradle module per feature, clear `:core` / `:feature:*` graph.
2. **Architecture** — Compose + Jetpack ViewModel, navigation, DI (Hilt/Koin).
3. **Native integrations** — Health Connect / Google Fit, WorkManager, foreground services, Widgets, Push.
4. **Data & sync** — local-first (Room / SQLDelight / DataStore), sync orchestration, conflict resolution.
5. **Claude Code integration** — one spec per feature, architecture rules pinned, code review checklist.
6. **Workflow** — spec → contracts → AI scaffold → integrations → QA. Branching, review, CI/CD.
7. **Performance** — Macrobenchmark, Perfetto, baseline profiles.
8. **Scaling** — adding features, onboarding, long-term consistency.
9. **Risks** — AI hallucinations, hidden complexity, background-execution gotchas.

Each phase must include Goals, Deliverables, Risks, and Exit Criteria.

Phases:
- Phase 0 — Validation / POC
- Phase 1 — Core Architecture Setup
- Phase 2 — Feature Development
- Phase 3 — Native Integrations
- Phase 4 — Optimization & Scale

Deliverables:
- Architecture diagram (text or Mermaid)
- Feature development lifecycle
- Practical workflow (battle-tested, not theoretical)
```

---

## Generated Output

### Architecture Overview

**Goal:** Build a scalable, maintainable Android app that ships features fast while maximizing native platform capabilities and using Claude Code as a force multiplier.

**Core Principles:**
- Feature-first modularization (not layer-first)
- Local-first data architecture
- Native-first integrations (no cross-platform compromises)
- AI-assisted development with human-verified contracts
- Performance baked in, not bolted on

---

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                          :app                               │
│  (Compose UI, Navigation, DI Container, MainActivity)       │
└───────────────────┬─────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┬───────────┬────────────┐
        │           │           │           │            │
┌───────▼─────┐ ┌──▼──────┐ ┌──▼──────┐ ┌──▼──────┐ ┌───▼────────┐
│:feature:home│ │:feature:│ │:feature:│ │:feature:│ │:feature:*  │
│             │ │ profile │ │ workout │ │ sync    │ │ (future)   │
│ - UI        │ │         │ │         │ │         │ │            │
│ - ViewModel │ │ - UI    │ │ - UI    │ │ - UI    │ │            │
│ - Nav       │ │ - VM    │ │ - VM    │ │ - Worker│ │            │
└─────┬───────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────────────┘
      │              │           │           │
      └──────────────┼───────────┼───────────┘
                     │           │
         ┌───────────▼───────────▼───────────┐
         │          :core:domain              │
         │  (UseCases, Models, Contracts)     │
         └───────────┬────────────────────────┘
                     │
         ┌───────────▼───────────────────────┐
         │          :core:data                │
         │  (Room, Repositories, DataStore)   │
         └───────────┬────────────────────────┘
                     │
         ┌───────────┴────────────┬───────────────┬─────────────┐
         │                        │               │             │
    ┌────▼─────┐         ┌────────▼──────┐  ┌────▼──────┐  ┌───▼─────┐
    │:core:    │         │:core:health   │  │:core:work │  │:core:   │
    │ network  │         │ (Health       │  │ (Worker   │  │ widget  │
    │          │         │  Connect)     │  │  Manager) │  │         │
    └──────────┘         └───────────────┘  └───────────┘  └─────────┘
```

**Module Dependency Rules:**
- `:app` → depends on all `:feature:*` modules
- `:feature:*` → depends only on `:core:*` modules (never on other features)
- `:core:domain` → pure Kotlin, no Android dependencies
- `:core:data` → depends on `:core:domain` and data sources (Room, network)
- `:core:*` utilities → leaf modules (minimal dependencies)

---

### Phase 0 — Validation / POC

**Goals:**
- Validate that Compose + Hilt + Room stack works
- Test Claude Code's ability to scaffold basic features
- Identify early integration blockers (Health Connect permissions, WorkManager)

**Deliverables:**
1. **Single-feature prototype** — One working feature (e.g., "Home screen with step count")
2. **Architecture decision record (ADR)** — Document key choices:
   - DI: Hilt vs Koin (recommended: Hilt for type safety + Android integration)
   - Data: Room vs SQLDelight (recommended: Room for standard cases, SQLDelight if multi-platform future)
   - Navigation: Compose Navigation vs Voyager (recommended: official Compose Navigation)
3. **Claude Code test** — Write one feature spec, generate scaffold, verify output quality
4. **Build.gradle setup** — Module structure, version catalogs, convention plugins

**Risks:**
- Health Connect not available on emulator (need physical device or mock)
- Claude Code generates Compose code with deprecated APIs
- DI setup too complex for AI to maintain

**Exit Criteria:**
- [ ] One feature compiles and runs
- [ ] Module graph is clean (verified with `./gradlew :app:dependencies --configuration debugRuntimeClasspath`)
- [ ] Claude Code successfully generated 80%+ of scaffold code with minimal fixes
- [ ] ADRs approved and committed

---

### Phase 1 — Core Architecture Setup

**Goals:**
- Lock in module structure and dependency rules
- Set up core infrastructure (DI, database, navigation)
- Establish Claude Code integration points

**Deliverables:**

#### 1.1 Module Structure
```
app/
  src/main/
    AndroidManifest.xml
    MainActivity.kt
    NavGraph.kt
    di/
      AppModule.kt

feature/
  home/
    build.gradle.kts
    src/main/
      HomeScreen.kt
      HomeViewModel.kt
  profile/
  workout/
  sync/

core/
  domain/
    src/main/kotlin/
      model/
      usecase/
      repository/  (interfaces only)
  data/
    src/main/kotlin/
      repository/  (implementations)
      local/
        AppDatabase.kt
        dao/
      remote/
        ApiService.kt
  network/
  health/
    HealthConnectManager.kt
  work/
    SyncWorker.kt
  widget/

buildSrc/  (or build-logic/)
  src/main/kotlin/
    AndroidFeatureConventionPlugin.kt
    AndroidLibraryConventionPlugin.kt
```

#### 1.2 Core Infrastructure

**Database (Room):**
```kotlin
// :core:data
@Database(
    entities = [WorkoutEntity::class, ProfileEntity::class],
    version = 1
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun workoutDao(): WorkoutDao
    abstract fun profileDao(): ProfileDao
}

// DI setup
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "app-database"
        ).build()
    }
}
```

**Navigation:**
```kotlin
// :app/NavGraph.kt
@Composable
fun AppNavGraph(navController: NavHostController) {
    NavHost(navController, startDestination = "home") {
        composable("home") { HomeScreen() }
        composable("profile") { ProfileScreen() }
        composable("workout/{id}") { WorkoutDetailScreen() }
    }
}
```

**DI (Hilt):**
```kotlin
// :app/MainActivity.kt
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AppTheme {
                val navController = rememberNavController()
                AppNavGraph(navController)
            }
        }
    }
}
```

#### 1.3 Architecture Rules (pinned for Claude Code)

Create `/ARCHITECTURE.md`:

```markdown
# Architecture Rules

## Module Dependency Rules
1. `:feature:*` modules NEVER depend on other features
2. All business logic goes in `:core:domain` (pure Kotlin)
3. All data access goes through Repository interfaces
4. ViewModels live in feature modules, UseCases in :core:domain

## Code Conventions
1. **Compose UI:** Every screen = one `@Composable` function + one `ViewModel`
2. **State:** Use `StateFlow` for UI state, never `LiveData`
3. **Navigation:** Destinations defined as sealed class in `:app/navigation/`
4. **DI:** Constructor injection only, no `@Inject lateinit var`

## AI (Claude Code) Integration
1. One spec per feature in `/specs/features/`
2. Spec must define: API contracts, data models, UI states, error cases
3. Claude generates: ViewModels, UseCases, Repository interfaces, Compose UI scaffold
4. Human verifies: business logic, error handling, performance implications
5. Before merging AI-generated code: run `./gradlew detekt` + manual code review

## Performance Budgets
- Screen launch: < 500ms (cold start to first frame)
- Database query: < 16ms (avoid main thread blocking)
- API response: < 2s (with loading state)

## Testing Strategy
- Unit tests: UseCases (in :core:domain)
- Integration tests: Repositories (with in-memory Room)
- UI tests: One happy path per feature (Compose Testing)
- Performance tests: Macrobenchmark for critical flows
```

**Risks:**
- Module graph gets polluted (feature modules start depending on each other)
- Claude Code generates code that violates architecture rules (no validation)
- Hilt setup too verbose for developers to understand

**Exit Criteria:**
- [ ] All core modules created and compile
- [ ] Module dependency graph validated (no cycles, no feature-to-feature deps)
- [ ] ARCHITECTURE.md committed and reviewed
- [ ] One reference feature implemented following all rules

---

### Phase 2 — Feature Development

**Goals:**
- Ship 3-5 features using AI-assisted workflow
- Validate Claude Code integration at scale
- Establish feature development lifecycle

**Deliverables:**

#### 2.1 Feature Development Workflow

```
1. SPEC (Human)
   └─> Write /specs/features/workout-tracking.md
       - User stories
       - API contracts
       - Data models
       - UI states
       - Error cases
       - Acceptance criteria

2. CONTRACTS (Human)
   └─> Define interfaces (before AI generation)
       - Repository interface in :core:domain
       - API response models in :core:data
       - UI state data class in :feature:workout

3. SCAFFOLD (Claude Code)
   └─> Prompt: "Generate feature:workout following ARCHITECTURE.md"
       - ViewModel + UI state
       - UseCase implementation
       - Repository implementation
       - Compose UI scaffold (no business logic)
       - Navigation integration

4. INTEGRATION (Human)
   └─> Add native integrations Claude cannot generate:
       - Health Connect permissions
       - WorkManager scheduling
       - Widget updates
       - Push notification handling

5. QA (Human + AI)
   └─> Human: Test on device, edge cases
   └─> Claude: Generate unit tests for UseCases
   └─> CI: Run detekt, unit tests, Macrobenchmark
```

#### 2.2 Claude Code Prompts (Templates)

**Feature Scaffold Prompt:**
```
Generate a new feature module `:feature:workout` following /ARCHITECTURE.md.

Requirements:
- Read /specs/features/workout-tracking.md for requirements
- Generate WorkoutViewModel with state: Loading, Success, Error
- Generate WorkoutScreen.kt (Compose UI) with:
  - LazyColumn of workout items
  - FloatingActionButton to add workout
  - Error/loading states
- Generate WorkoutUseCase in :core:domain
- Generate WorkoutRepository interface in :core:domain
- Generate WorkoutRepositoryImpl in :core:data (Room-backed)
- Update :app/navigation/NavGraph.kt to add workout route

DO NOT generate:
- Health Connect integration (human will add)
- WorkManager sync logic (human will add)
- Complex business logic in ViewModel (belongs in UseCase)

Output:
- List of files created
- Summary of what still needs human work
```

**Code Review Prompt:**
```
Review the AI-generated code in :feature:workout for:

1. Architecture violations (check ARCHITECTURE.md)
2. Missing error handling
3. Performance issues (main thread blocking, infinite recomposition)
4. Accessibility (content descriptions, semantics)
5. Missing tests

Output findings as checklist with file:line references.
```

#### 2.3 Features to Implement

1. **Home Dashboard** — Step count, calories, recent workouts
2. **Workout Tracking** — Log workout, view history
3. **Profile** — User settings, health data permissions
4. **Sync** — Background sync with Health Connect
5. **Widget** — Today's step count on home screen

**Risks:**
- Claude generates features that compile but have subtle bugs
- Developers skip contract-definition step and let AI infer contracts
- Feature creep (Claude suggests "improvements" that add complexity)

**Exit Criteria:**
- [ ] 5 features shipped and tested on device
- [ ] All features follow ARCHITECTURE.md (verified by human review)
- [ ] Claude Code successfully generated 70%+ of feature code (measured by LOC)
- [ ] Zero module dependency violations (verified by dependency graph)

---

### Phase 3 — Native Integrations

**Goals:**
- Integrate platform-specific capabilities (Health Connect, WorkManager, Widgets)
- Ensure Claude Code does NOT generate broken native code
- Document integration patterns for future features

**Deliverables:**

#### 3.1 Health Connect Integration

**Contract (Human-defined):**
```kotlin
// :core:health/HealthRepository.kt
interface HealthRepository {
    suspend fun getTodaySteps(): Result<Int>
    suspend fun getWorkouts(dateRange: DateRange): Result<List<Workout>>
    suspend fun requestPermissions(activity: Activity): Boolean
}
```

**Implementation (Human-written):**
```kotlin
// :core:health/HealthConnectManager.kt
class HealthConnectManager @Inject constructor(
    private val context: Context
) : HealthRepository {
    
    private val healthConnectClient by lazy {
        HealthConnectClient.getOrCreate(context)
    }
    
    override suspend fun getTodaySteps(): Result<Int> {
        return try {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        startTime = LocalDate.now().atStartOfDay(),
                        endTime = LocalDate.now().atTime(23, 59)
                    )
                )
            )
            Result.success(response.records.sumOf { it.count })
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    // ... other methods
}
```

**Claude Code Role:**
- Generate ViewModel that calls `HealthRepository.getTodaySteps()`
- Generate UI that shows loading/success/error states
- **DO NOT** generate Health Connect SDK calls (high error rate)

#### 3.2 WorkManager Integration

**Contract (Human-defined):**
```kotlin
// :core:work/SyncScheduler.kt
interface SyncScheduler {
    fun schedulePeriodicSync()
    fun cancelSync()
}
```

**Implementation (Human-written):**
```kotlin
// :core:work/SyncWorker.kt
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val healthRepository: HealthRepository,
    private val workoutRepository: WorkoutRepository
) : CoroutineWorker(context, params) {
    
    override suspend fun doWork(): Result {
        return try {
            // Sync health data
            val steps = healthRepository.getTodaySteps().getOrThrow()
            workoutRepository.updateTodaySteps(steps)
            
            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) Result.retry()
            else Result.failure()
        }
    }
}

// :core:work/SyncSchedulerImpl.kt
class SyncSchedulerImpl @Inject constructor(
    private val workManager: WorkManager
) : SyncScheduler {
    
    override fun schedulePeriodicSync() {
        val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(
            repeatInterval = 1, 
            repeatIntervalTimeUnit = TimeUnit.HOURS
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()
        
        workManager.enqueueUniquePeriodicWork(
            "health-sync",
            ExistingPeriodicWorkPolicy.KEEP,
            syncRequest
        )
    }
}
```

**Claude Code Role:**
- Generate Settings screen UI that calls `SyncScheduler.schedulePeriodicSync()`
- **DO NOT** generate Worker implementation (complex failure handling)

#### 3.3 Widget Integration

**Contract (Human-defined):**
```kotlin
// :core:widget/WidgetUpdater.kt
interface WidgetUpdater {
    suspend fun updateStepCountWidget(steps: Int)
}
```

**Implementation (Human-written):**
```kotlin
// :core:widget/StepCountWidget.kt
class StepCountWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val steps = loadStepCount(context)
            StepCountWidgetContent(steps)
        }
    }
}

@Composable
fun StepCountWidgetContent(steps: Int) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.primaryContainer)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Today's Steps", style = TextStyle(fontSize = 16.sp))
        Text(steps.toString(), style = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold))
    }
}
```

**Claude Code Role:**
- Generate widget update calls from ViewModel after data sync
- **DO NOT** generate Glance widget UI (experimental APIs, high error rate)

#### 3.4 Integration Patterns Document

Create `/docs/NATIVE_INTEGRATIONS.md`:

```markdown
# Native Integration Patterns

## Health Connect
**Human writes:** SDK calls, permission handling, error mapping
**Claude generates:** ViewModel layer, UI state handling
**Contract:** `HealthRepository` interface

## WorkManager
**Human writes:** Worker implementation, retry logic, constraint setup
**Claude generates:** Scheduling UI, settings persistence
**Contract:** `SyncScheduler` interface

## Widgets
**Human writes:** Glance widget UI, data loading
**Claude generates:** Widget update triggers from app
**Contract:** `WidgetUpdater` interface

## Push Notifications
**Human writes:** FCM token registration, notification channel setup
**Claude generates:** In-app notification UI, permission request flow
**Contract:** `NotificationManager` interface

## Rule: Claude never directly generates native SDK calls
Always define a Repository/Manager interface first.
```

**Risks:**
- Developers let Claude generate native code, leading to runtime crashes
- Missing permissions in manifest (AI doesn't update XML reliably)
- Background execution limits not handled (WorkManager constraints wrong)

**Exit Criteria:**
- [ ] Health Connect integration works on physical device
- [ ] WorkManager syncs data in background (verified with WorkManager inspector)
- [ ] Widget updates reliably
- [ ] NATIVE_INTEGRATIONS.md committed and followed by team

---

### Phase 4 — Optimization & Scale

**Goals:**
- Optimize critical paths (app startup, database queries, UI rendering)
- Scale to 10+ features without performance degradation
- Establish long-term maintenance practices

**Deliverables:**

#### 4.1 Performance Optimization

**App Startup:**
- Run Macrobenchmark: `./gradlew :benchmark:connectedCheck`
- Target: Cold start < 1000ms, warm start < 300ms
- Optimizations:
  - Lazy DI initialization (Hilt `@Singleton` with lazy injection)
  - Deferred WorkManager scheduling (not in `onCreate`)
  - R8 code shrinking + baseline profiles

**Database Queries:**
- Add Room query logging: `RoomDatabase.Builder().setQueryCallback()`
- Identify slow queries (> 16ms = one frame drop)
- Optimizations:
  - Indices on frequently queried columns
  - Pagination for large lists (Paging 3)
  - Pre-populate database with default data

**UI Rendering:**
- Use Compose Layout Inspector to find unnecessary recompositions
- Optimizations:
  - `remember` expensive computations
  - `derivedStateOf` for computed state
  - `key()` in LazyColumn for stable item identity

**Baseline Profiles:**
```bash
# Generate baseline profile
./gradlew :app:generateBaselineProfile

# Verify improvement
./gradlew :benchmark:connectedCheck --rerun-tasks
```

#### 4.2 Scaling to 10+ Features

**Module Convention Plugins (DRY up build.gradle):**

```kotlin
// buildSrc/AndroidFeatureConventionPlugin.kt
class AndroidFeatureConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            with(pluginManager) {
                apply("com.android.library")
                apply("org.jetbrains.kotlin.android")
                apply("com.google.dagger.hilt.android")
                apply("org.jetbrains.kotlin.plugin.compose")
            }
            
            extensions.configure<LibraryExtension> {
                compileSdk = 34
                defaultConfig {
                    minSdk = 26
                }
                composeOptions {
                    kotlinCompilerExtensionVersion = "1.5.3"
                }
            }
            
            dependencies {
                add("implementation", project(":core:domain"))
                add("implementation", libs.findLibrary("androidx.compose.ui").get())
                add("implementation", libs.findLibrary("hilt.android").get())
                // ... common feature dependencies
            }
        }
    }
}
```

**Feature Module Template (for Claude):**

Create `/docs/FEATURE_TEMPLATE.md`:

```markdown
# Feature Module Template

Use this template when generating new features.

## File Structure
```
feature/<name>/
  build.gradle.kts  → apply(plugin = "android.feature.convention")
  src/main/
    <Name>Screen.kt   → Main composable
    <Name>ViewModel.kt → State + logic
    navigation/
      <Name>Destination.kt → Navigation args
```

## ViewModel Template
```kotlin
@HiltViewModel
class WorkoutViewModel @Inject constructor(
    private val getWorkoutsUseCase: GetWorkoutsUseCase
) : ViewModel() {
    
    private val _state = MutableStateFlow<WorkoutState>(WorkoutState.Loading)
    val state: StateFlow<WorkoutState> = _state.asStateFlow()
    
    init {
        loadWorkouts()
    }
    
    private fun loadWorkouts() {
        viewModelScope.launch {
            getWorkoutsUseCase()
                .onSuccess { workouts -> _state.value = WorkoutState.Success(workouts) }
                .onFailure { error -> _state.value = WorkoutState.Error(error.message) }
        }
    }
}

sealed interface WorkoutState {
    data object Loading : WorkoutState
    data class Success(val workouts: List<Workout>) : WorkoutState
    data class Error(val message: String?) : WorkoutState
}
```

## Screen Template
```kotlin
@Composable
fun WorkoutScreen(viewModel: WorkoutViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    
    WorkoutContent(
        state = state,
        onRetry = { viewModel.loadWorkouts() }
    )
}

@Composable
private fun WorkoutContent(
    state: WorkoutState,
    onRetry: () -> Unit
) {
    when (state) {
        is WorkoutState.Loading -> LoadingIndicator()
        is WorkoutState.Success -> WorkoutList(state.workouts)
        is WorkoutState.Error -> ErrorView(state.message, onRetry)
    }
}
```

When generating a feature, Claude should:
1. Copy this template
2. Replace `Workout` with feature name
3. Add feature-specific UI in `WorkoutContent`
4. Define UseCase contract in :core:domain
```

#### 4.3 Long-Term Consistency

**Code Review Checklist (for human reviewers):**

```markdown
# AI-Generated Code Review Checklist

Before merging Claude-generated code, verify:

## Architecture
- [ ] No feature-to-feature dependencies (check imports)
- [ ] Business logic in UseCase, not ViewModel
- [ ] Repository pattern used for data access

## Performance
- [ ] No blocking calls in ViewModels (suspend functions only)
- [ ] Database queries use indices
- [ ] No unnecessary recomposition (check `remember`, `derivedStateOf`)

## Error Handling
- [ ] All network/database calls wrapped in try-catch or Result
- [ ] Error states shown in UI (not silent failures)
- [ ] User-facing error messages (not stack traces)

## Testing
- [ ] UseCase has unit tests
- [ ] ViewModel has unit tests for all state transitions
- [ ] One UI test per feature (happy path)

## Native Integrations
- [ ] No direct SDK calls in ViewModels (must go through Repository)
- [ ] Permissions requested with rationale UI
- [ ] Background work uses WorkManager (not foreground service)

## Accessibility
- [ ] Composables have content descriptions
- [ ] Touch targets >= 48dp
- [ ] Color contrast >= 4.5:1
```

**Onboarding New Developers:**

1. Read `/ARCHITECTURE.md` (architecture rules)
2. Read `/docs/NATIVE_INTEGRATIONS.md` (integration patterns)
3. Read `/docs/FEATURE_TEMPLATE.md` (feature development)
4. Pick one existing feature, trace through all layers (UI → ViewModel → UseCase → Repository)
5. Generate one new feature with Claude Code following the template
6. Submit for code review (use checklist above)

**Dependency Updates:**

```bash
# Use Gradle Version Catalog
# gradle/libs.versions.toml

[versions]
compose = "1.5.3"
hilt = "2.48"
room = "2.6.0"

[libraries]
androidx-compose-ui = { module = "androidx.compose.ui:ui", version.ref = "compose" }
hilt-android = { module = "com.google.dagger:hilt-android", version.ref = "hilt" }
room-runtime = { module = "androidx.room:room-runtime", version.ref = "room" }
```

Update strategy:
- Major versions: human evaluation (breaking changes)
- Minor/patch versions: automated with Renovate/Dependabot
- Test suite must pass before merging updates

**Risks:**
- Performance regressions go unnoticed (no continuous benchmarking)
- New developers bypass architecture rules (not enforced by linter)
- Claude Code gets better and generates code that doesn't match old patterns (templates stale)

**Exit Criteria:**
- [ ] App startup < 1000ms (cold), < 300ms (warm)
- [ ] 10 features implemented with zero performance regressions
- [ ] Baseline profiles generated and validated
- [ ] Code review checklist used on 100% of AI-generated code
- [ ] Onboarding doc tested with new developer

---

## Summary of Risks and Mitigations

### Risk: AI Hallucinations
**Mitigation:** 
- Define contracts (interfaces) before AI generation
- Human review all generated code with checklist
- Pin architecture rules in ARCHITECTURE.md
- Never merge AI code without running on device

### Risk: Hidden Complexity
**Mitigation:**
- Feature-first modules (vertical slices, not horizontal layers)
- Strict dependency rules (no feature-to-feature)
- Module dependency graph validation in CI

### Risk: Background Execution Gotchas
**Mitigation:**
- All background work uses WorkManager (no manual threads)
- Doze mode testing on physical device
- Background execution limits documented in NATIVE_INTEGRATIONS.md

### Risk: Performance Degradation at Scale
**Mitigation:**
- Macrobenchmark in CI (fail build if startup > 1s)
- Room query logging in debug builds
- Baseline profiles for production builds

### Risk: Claude Code Generates Deprecated APIs
**Mitigation:**
- Lint rules enforced in CI (`./gradlew lint`)
- Detekt custom rules for Compose best practices
- Human review focuses on API usage

---

## Workflow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│  Feature Development Lifecycle (Battle-Tested)                  │
└─────────────────────────────────────────────────────────────────┘

1. HUMAN: Write spec in /specs/features/<name>.md
   ├─ User stories
   ├─ API contracts
   ├─ Data models
   ├─ Error cases
   └─ Acceptance criteria

2. HUMAN: Define contracts in :core:domain
   ├─ UseCase interface
   ├─ Repository interface
   └─ Domain models

3. CLAUDE: Generate feature scaffold
   ├─ Prompt: "Generate :feature:<name> following ARCHITECTURE.md"
   ├─ Output: ViewModel, Screen, Repository impl
   └─ Human verifies: compiles, follows patterns

4. HUMAN: Add native integrations
   ├─ Health Connect SDK calls
   ├─ WorkManager setup
   ├─ Widget updates
   └─ Push notifications

5. CLAUDE: Generate tests
   ├─ UseCase unit tests
   ├─ ViewModel unit tests
   └─ Human writes: UI test (one happy path)

6. HUMAN: Code review
   ├─ Run checklist from ARCHITECTURE.md
   ├─ Test on physical device
   └─ Check performance (no frame drops)

7. CI/CD: Automated checks
   ├─ ./gradlew detekt
   ├─ ./gradlew test
   ├─ ./gradlew :benchmark:connectedCheck
   └─ ./gradlew lint

8. MERGE: Ship feature
   └─ Update CHANGELOG.md (human-written)
```

---

## Expected Artifacts (to be created in repo)

1. `/ARCHITECTURE.md` — Architecture rules and conventions
2. `/docs/NATIVE_INTEGRATIONS.md` — Integration patterns for Health Connect, WorkManager, etc.
3. `/docs/FEATURE_TEMPLATE.md` — Template for new feature modules
4. `/specs/features/` — Feature specs (one per feature)
5. `/.claude/prompts/feature-scaffold.md` — Claude Code prompt templates
6. `/.claude/prompts/code-review.md` — Claude Code review prompts
7. `/buildSrc/` or `/build-logic/` — Convention plugins for modules
8. `/gradle/libs.versions.toml` — Version catalog

---

## Final Checklist (Before Considering Architecture "Locked")

- [ ] Phase 0 complete: POC validated
- [ ] Phase 1 complete: Core architecture set up, ARCHITECTURE.md committed
- [ ] Phase 2 complete: 3+ features shipped using AI workflow
- [ ] Phase 3 complete: Health Connect + WorkManager + Widgets integrated
- [ ] Phase 4 complete: Performance optimized, baseline profiles generated
- [ ] All architecture artifacts committed to repo
- [ ] Team trained on workflow (at least one feature per developer)
- [ ] CI/CD pipeline enforces architecture rules

---

## Observations

**What Worked:**
- Feature-first modularization keeps modules small and focused
- Strict dependency rules (no feature-to-feature) prevent spaghetti architecture
- Human-defined contracts before AI generation reduces hallucinations
- Baseline profiles provide measurable performance improvements

**What Needs Iteration:**
- Claude Code struggles with Compose experimental APIs (Glance widgets)
- WorkManager retry logic too complex for AI (needs human review)
- Health Connect permissions vary by Android version (needs device testing)

**Recommended Next Steps:**
1. Implement Phase 0 with one reference feature
2. Validate Claude Code can follow ARCHITECTURE.md (measure: % of generated code that needs fixes)
3. Document any gaps in architecture rules
4. Iterate on FEATURE_TEMPLATE.md based on real feature development

---

## Success Metrics (3 months post-implementation)

- **Velocity:** Ship one feature per week (with 2-person team)
- **Quality:** < 5% of AI-generated code requires major refactor
- **Performance:** App startup < 1s, zero ANRs in production
- **Consistency:** 100% of features follow ARCHITECTURE.md (verified by code review)
- **Adoption:** New developer productive within 1 week (ships first feature)

---

**End of Reproduction**
