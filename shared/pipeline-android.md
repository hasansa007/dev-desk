# Pipeline — Android Additions

Apply these additions to Phases 8, 9, and 10 when the detected stack is **Android only** (`build.gradle*` + Android manifest, no iOS).

---

## Phase 8 — Android Additions

### UI Previews
Add `@Preview` annotations with `@PreviewParameter` for data variants on all new Composables.

### Localization Audit
Scan the diff for newly introduced user-visible strings:
- Reference a `strings.xml` resource key
- Add to every `res/values-<locale>/strings.xml` for all supported locales
- Draft baseline translations for all supported languages when adding new strings

### Release Notes Draft
Draft Play Store "What's New" copy:
- **Major features:** New flows, screens, or significant new capabilities
- **Minor features / improvements:** UI tweaks, UX polish, behavioral changes
- **Bug fixes:** Issues resolved (reference ticket/issue ID)

**Platform isolation rule:** Android release notes must NEVER mention iOS. Describe from the Android user's perspective only. Do not say "now matches iOS."

---

## Phase 9 — Android Build & Verification (agent-run via adb)

Build + launch on the **emulator** yourself via the `run` skill (`/run android emulator`); ask about a physical device only when the row genuinely needs hardware (camera, sensors, real notifications).

**Execute the checklist yourself** — the emulator is fully drivable over adb:

```bash
adb exec-out uiautomator dump /dev/tty        # view hierarchy → find the node's bounds
adb shell input tap <x> <y>                   # tap it (center of bounds)
adb shell input text 'value'  /  input keyevent 66   # type + enter
adb exec-out screencap -p > row-N.png         # evidence screenshot per row
adb logcat -d -s <AppTag>:* AndroidRuntime:E  # crashes + app errors after each flow
```

Loop per row: dump hierarchy → act → screenshot → check logcat. Mark ✅/❌ with the screenshot + any error lines. Hand the developer only hardware-bound rows plus the prod decision.
