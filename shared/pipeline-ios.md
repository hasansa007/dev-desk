# Pipeline — iOS Additions

Apply these additions to Phases 8, 9, and 10 when the detected stack is **iOS only** (`*.xcodeproj` / `Package.swift`, Swift only).

---

## Phase 8 — iOS Additions

### UI Previews
Add `#Preview` macro per state/flow. Use realistic production-shaped fixture data — not placeholder strings.

### Localization Audit
Scan the diff for newly introduced user-visible strings:
- Wrap in `String(localized:)` / `LocalizedStringKey`
- Add to every `.strings` / `.xcstrings` for all supported languages
- Draft baseline translations for all supported languages when adding new strings

### Release Notes Draft
Draft App Store "What's New" copy:
- **Major features:** New flows, screens, or significant new capabilities
- **Minor features / improvements:** UI tweaks, UX polish, behavioral changes
- **Bug fixes:** Issues resolved (reference ticket/issue ID)

**Platform isolation rule:** iOS release notes must NEVER mention Android. Describe from the iOS user's perspective only. Do not say "now matches Android."

---

## Phase 9 — iOS Build & Verification (agent-run on the simulator)

Build + launch on the **simulator** yourself via the `run` skill (`/run ios sim`); ask about a physical device only when the row needs hardware.

**Execute what the simulator can reach:**

```bash
xcrun simctl openurl booted '<scheme-or-universal-link>'   # drive to a screen via deep link
xcrun simctl io booted screenshot row-N.png                # evidence screenshot per row
xcrun simctl spawn booted log show --last 2m --predicate 'processImagePath contains "<AppName>"'  # app errors
xcrun simctl push / privacy / status_bar                   # notifications, permissions, clean status bar
```

- **If the project has a UI-test target (XCUITest):** write/extend a test per checklist row and run it — that's full tap-level automation.
- **Without one**, simctl has no tap injection: cover rows reachable via deep links + launch states, screenshot each, and hand the developer the interaction-only rows explicitly.

Mark ✅/❌ with evidence. The developer gets the can't-reach list plus the prod decision — not the whole checklist.
