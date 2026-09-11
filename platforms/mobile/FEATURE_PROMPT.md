# Feature Prompt — Conditional by Stack

> Use the section that matches the project. Detect from Phase 2 (Tech Stack & Project Discovery). Skip sections for platforms the project does not target.

---

## Header (always)

```
# Feature Prompt: [Feature Name]

Implement the feature: [describe feature clearly]

## Product Behavior
[Explain what the user should see/do]

## Acceptance Criteria
- [Criterion 1]
- [Criterion 2]
- [Criterion 3]
```

---

## Variant A — iOS only

```
## iOS Scope
Implement using native iOS patterns:
- Swift / SwiftUI (or UIKit if the project uses it)
- Native navigation
- Platform permissions
- HealthKit / Apple Watch / WidgetKit / BGTasks if needed

## Out of Scope
- Anything platform-specific to Android
- Cross-platform abstractions

## Claude Code Instructions
1. Inspect existing files first.
2. Show proposed file changes before writing.
3. Generate implementation in small safe steps.
4. Match existing module conventions (naming, DI, navigation).
5. Add tests where appropriate (unit + snapshot/UI).
6. Provide a final QA checklist.

## Output Required
- Architecture impact summary
- Files changed
- Tests added
- Manual QA checklist
- Known risks
```

---

## Variant B — Android only

```
## Android Scope
Implement using native Android patterns:
- Kotlin / Jetpack Compose (or Views if the project uses them)
- Native navigation
- Platform permissions
- Health Connect / Google Fit / WorkManager / Widgets if needed

## Out of Scope
- Anything platform-specific to iOS
- Cross-platform abstractions

## Claude Code Instructions
1. Inspect existing files first.
2. Show proposed file changes before writing.
3. Generate implementation in small safe steps.
4. Match existing module conventions (naming, DI, navigation).
5. Add tests where appropriate (unit + Compose UI / instrumented).
6. Provide a final QA checklist.

## Output Required
- Architecture impact summary
- Files changed
- Tests added
- Manual QA checklist
- Known risks
```

---

## Variant C — iOS + Android + KMP

```
## Shared KMP Scope
Only include:
- Domain models
- Business rules
- Validation
- API contracts
- Sync contracts

Do NOT include:
- UI
- Navigation
- Native permissions
- HealthKit / Google Fit / Health Connect
- Background workers
- Platform animations

## iOS Scope
Implement using native iOS patterns:
- Swift / SwiftUI
- Native navigation
- Platform permissions
- HealthKit / Apple Watch if needed

## Android Scope
Implement using native Android patterns:
- Kotlin / Jetpack Compose
- Native navigation
- Platform permissions
- Google Fit / Health Connect if needed

## Claude Code Instructions
1. Inspect existing files first.
2. Show proposed file changes before writing.
3. Generate implementation in small safe steps (shared → iOS → Android).
4. Keep iOS and Android behavior aligned to the same acceptance criteria.
5. Add tests where appropriate (KMP unit, iOS unit/snapshot, Android unit/Compose).
6. Provide a final parity checklist (iOS vs Android behavior).

## Output Required
- Architecture impact summary
- Files changed (shared / iOS / Android)
- Tests added
- Manual QA checklist (per platform)
- Parity checklist
- Known risks
```
