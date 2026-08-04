# Pipeline — KMP Additions

Apply these additions to Phases 10, 11, and 14 when the detected stack is **KMP** (`androidApp/` + `iOSApp/` + `shared/`).

---

## Phase 10 — KMP Additions

### UI Previews
- **iOS (SwiftUI):** Add `#Preview` macro per state/flow. Use realistic production-shaped fixture data.
- **Android (Compose):** Add `@Preview` annotations with `@PreviewParameter` for data variants.

### Localization Audit
Scan the diff for newly introduced user-visible strings:
- **iOS:** Wrap in `String(localized:)` / `LocalizedStringKey`. Add to every `.strings` / `.xcstrings`.
- **Android:** Reference a `strings.xml` key. Add to every `res/values-<locale>/strings.xml`.
- Draft baseline translations for all supported languages on both platforms.

### Parity Check
After implementation, verify iOS and Android behavior is aligned to the same acceptance criteria. Flag any divergence.

### Release Notes Draft
Draft **two separate** release notes — one per store:

**App Store (iOS):**
- Describe from the iOS user's perspective only
- Never mention Android

**Play Store (Android):**
- Describe from the Android user's perspective only
- Never mention iOS

Cross-platform parity changes: include on both lists, described from each platform's perspective independently.

---

## Phase 11 — KMP Build & Verification (agent-run, both platforms)

Launch BOTH targets yourself via the `dev:run` skill (`/dev:run android emulator`, `/dev:run ios sim`) and execute the checklist on each, using each platform's own mechanics:

- **Android:** full adb automation — see `pipeline-android.md` Phase 11 (hierarchy dump → tap → screenshot → logcat).
- **iOS:** simctl deep links + screenshots, XCUITest when a UI-test target exists — see `pipeline-ios.md` Phase 11.

Run the same rows on both and compare the evidence side by side — that screenshot pair IS the Phase 10 parity check made concrete. Flag any divergence.

Hand the developer only hardware-bound / interaction-only-iOS rows plus the prod decision.
