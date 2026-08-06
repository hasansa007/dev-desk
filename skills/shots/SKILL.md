---
name: shots
description: >
  CAPTURES screens from the running app — iOS, Android and web — and optionally post-processes them
  into App Store / Play Store dimensions. A door into `dev:launch`: it reuses that skill's project
  discovery and its "reuse a server that is already up, start nothing" rule, then captures.
  Takes the CURRENT screen by default (`simctl io` · `adb screencap` · Chrome DevTools MCP), and
  drives the project's OWN screen-walking automation when it has one (a screenshot UITest scheme,
  a fastlane Snapfile, a Playwright/Cypress spec) for a full ordered, per-locale set.
  Store mode picks a DEVICE whose native resolution is already an accepted size rather than
  resizing — resizing is the fallback, never the method, and it never overwrites a source image.
  Trigger on: "take a screenshot", "screenshot the app", "capture the screen", "grab a screenshot
  of the simulator", "app store screenshots", "play store screenshots", "screenshots for the
  listing", "capture every screen", "resize the screenshots", "sort screenshots by language".
  NOT the Phase 11 evidence pass — that is `dev:verify`, which delegates capture here.
allowed-tools: [xcrun, adb, sips, xcodegen]
---

# shots — capture screens from the running app

A **tool**, not a phase: it reads none of `shared/pipeline.md`. Third verb of the family —
`launch` starts it, `launch-kill` stops it, `shots` shoots it.

**Not `dev:verify`.** Phase 11 gathers *evidence for a claim* and owns the reasoning about what to
prove. This owns the *mechanics of capture* and nothing else. Phase 11 delegates here.

## Phase 1 — Arguments

| Token | Meaning | Default |
|---|---|---|
| `ios` / `android` / `web` | Restrict to one platform | every platform `launch` 2.2 detects |
| `store` | Produce store-dimension, locale-sorted assets | plain capture |
| `flow` / `current` | Force the driven suite / force a single shot | auto (Phase 4) |
| `dry` | Report the plan, capture nothing | capture |
| A path | Output directory | `./shots/<platform>/` |

## Phase 2 — Discover — *point, do not restate*

Read `skills/launch/SKILL.md` and use unchanged:

| From `dev:launch` | For |
|---|---|
| **2.1** | `$PROJECT_ROOT` — worktree-safe (`git rev-parse --show-toplevel` first) |
| **2.2** | which platforms exist, and its precedence rules |
| **2.3.0** | **resolving the Xcode toolchain** — `xcrun simctl` fails outright when `xcode-select` points at Command Line Tools, even with Xcode installed |
| **2.3 / 2.4** | iOS scheme + bundle ID · Android package + activity |
| **2.6.2 / 2.6.3** | the web launch script and its port |

Two copies of project discovery drift, and a drift here captures the wrong app. Fix discovery in
`dev:launch`; both read it.

## Phase 3 — Make sure it is running — *point again*

Read `skills/launch/SKILL.md` Phase 3 and use it to get the app up.

**Inherit 3F.1 exactly: if something is already listening, reuse it and start nothing.** A capture
must never restart the developer's app — a launch script that frees the port first would kill their
process to take a picture of it. Record whether *this* run started anything; Phase 6 depends on it.

## Phase 4 — Capture

Choose the mode per platform. **Prefer the project's own screen-walking automation** — the same rule
`launch` applies to launch scripts, for the same reason: it knows the screens, the order and the
seed data, and you do not.

| Platform | Current screen | Driven flow — when the project has one |
|---|---|---|
| iOS sim | `xcrun simctl io booted screenshot "$OUT/$NAME.png"` | screenshot UITest scheme · `fastlane snapshot` |
| iOS device | the UITest suite (no direct `simctl` equivalent) | same |
| Android | `"$ADB" exec-out screencap -p > "$OUT/$NAME.png"` | UI Automator / Espresso suite |
| Web | Chrome DevTools MCP `take_screenshot` | Playwright / Cypress spec |

Detect a driven flow by presence, in this order: `Snapfile`/`Fastfile` → a screenshot UITest
**scheme** (in `project.yml` or `xcodebuild -list`) → `SnapshotHelper.swift` with no scheme wired →
a Playwright/Cypress config. Nothing found → current-screen capture, which always works.

**Resolve `adb` before using it — it is routinely installed but not on `PATH`:**

```bash
ADB=$(command -v adb || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")
[ -x "$ADB" ] || { echo "adb not found — install Android platform-tools"; }
```

> **2026-08-05, found before this skill ever ran.** On this machine `command -v adb` fails while
> `~/Library/Android/sdk/platform-tools/adb` exists and works. A bare `adb` would have reported
> "Android not available" on a machine where Android tooling is fully installed — a false negative,
> which is worse than an error. `dev:launch` already resolves the emulator this way (its 3C.1);
> this is the same fallback for the same reason.

**Multiple devices connected:** `"$ADB" -s <serial>` / `xcrun simctl io <udid>`. Never let the
target be implicit when more than one exists — say which was used, in the report.

### 4.1 — A disabled screenshot scheme is enabled automatically

When the suite exists but its scheme is commented out, uncomment it, run `xcodegen generate`, and
**print the diff you applied**. Then capture.

> **Deliberate divergence, decided 2026-08-05.** `dev:launch`'s Rules say *"Do NOT modify project
> files"* and *"Do NOT run `xcodegen generate` automatically"*. This skill overrides both, on the
> user's explicit instruction, because a commented-out scheme is the single thing standing between a
> complete ordered screenshot set and nothing at all. The divergence is written here rather than
> left implicit so the family does not silently contradict itself — and the diff is always printed,
> so the change never surfaces later as an unexplained edit in a working tree.

### 4.2 — Locales

The driven suites handle locale themselves (`snapshot` writes `ar-SA/`, `en-US/`). For
current-screen capture, relaunch the app per locale rather than resizing or re-labelling after
the fact:

```bash
xcrun simctl launch booted "$BUNDLE_ID" -AppleLanguages "(ar)" -AppleLocale ar_SA
```

## Phase 5 — Store mode: pick the DEVICE, do not resize

**The accepted-size list is not a constant to hard-code — it is a property of the device you
capture on.** So choose a simulator whose native resolution is already an accepted size and capture
there. A native capture is correct by construction and needs no post-processing at all.

Resizing is the **fallback**, only for images that already exist and cannot be re-captured. When it
is unavoidable:

```bash
sips -g pixelWidth -g pixelHeight "$f"          # read the real size FIRST
```

- **Never overwrite the source.** Write to an output directory. `sips -z` edits in place, and the
  original is unrecoverable.
- **Check the aspect ratio before resizing.** `-z H W` forces exact dimensions and will stretch an
  image whose ratio differs. If the ratio differs by more than ~1%, stop and say so — a distorted
  screenshot is worse than a missing one.
- **Never hard-code a target size.** Resolve it from the device, or from the accepted size closest
  to the source's own aspect ratio.

Then sort into locale folders and preserve ordering — App Store Connect displays by filename, which
is exactly why the driven suites name tests `test01_…`, `test06_…`. Keep those prefixes.

## Phase 6 — Report, then tear down what *you* started

```
## shots: <project>
iOS sim (iPhone 16 Pro Max, 1320×2868 native)  driven suite, 6 screens × ar,en  -> shots/ios/
Android (emulator-5554)                        current screen ×1                -> shots/android/
Web                                            reused :3007, started nothing    -> shots/web/

project.yml: screenshot scheme enabled (diff printed above), xcodegen re-run
Teardown: simulator left booted (yours) · dev server untouched (already up)
```

**Stop only what this run started**, by delegating to `dev:launch-kill`. Anything that was already
up is reported as untouched and never stopped. An unreported leftover is the process still running
tomorrow.

## Never

- **Restart a running app to photograph it.** Reuse it (Phase 3 / `launch` 3F.1).
- **Overwrite a source image**, or resize one whose aspect ratio does not match.
- **Hard-code store dimensions.** They change; a baked-in number goes stale silently.
- **Capture with an implicit target** when several devices are connected.
- **Claim a screen was captured without checking the file exists and is non-zero.**

## Known limits

| | |
|---|---|
| iOS **device** current-screen capture | No `simctl io` equivalent; needs the UITest suite. Simulator only for one-shot |
| Android locale switching | No clean per-launch flag like iOS; needs a device settings change. Driven suites handle it, one-shot does not |
| Store-size validation | Offline, the skill cannot know Apple's *current* accepted list. Capturing natively on a modern device sidesteps this; a resize path can only check self-consistency |
| Web full-page vs viewport | Chrome DevTools MCP captures the viewport by default; a full-page shot must be asked for explicitly |

## Scar tissue

**2026-08-05 — replaces `appstore-screenshots`, which had four defects.** That skill was 53 lines of
manual post-processing, and it existed only because a real project's screenshot automation — 11 ordered
UITests, a `SnapshotHelper`, a seeder — was unreachable behind a commented-out scheme. Both of its
steps were compensating for not running the suite.

1. `for f in *.png; do sips -z 2778 1284 "$f"; done` — **overwrote every original in place**, with
   no backup and no undo.
2. `-z` forces exact dimensions, so any source with a different aspect ratio was **silently
   stretched**.
3. `1284 × 2778` was **hard-coded**; Apple's primary requirement had already moved to 6.9".
4. Ordering was lost, though the suite's `test01_…` prefixes existed precisely to preserve it.

Fixed structurally rather than patched: capture natively on a correctly-sized device and the resize
step — with all three of its bugs — stops existing.

**2026-08-05 — the iOS one-shot path, run for real.** Booted `iPhone 17 Pro Max`, captured with
`xcrun simctl io booted screenshot`:

```
1320 × 2868   ratio 0.46025   ← Apple's 6.9" size, correct with no post-processing
```

The old skill's `sips -z 2778 1284` would have taken that and forced it to `1284 × 2778`
(ratio 0.46220) — a **0.42% aspect distortion, applied in place over the only copy**, turning a
currently-correct asset into an older size. This is the whole redesign in one measurement: choosing
the device removes the resize step and all three of its bugs at once. Simulator was booted by this
run and shut down by it.

**Undated, therefore unproven:** every driven-flow path (iOS UITest, Android suite, Playwright), the
Android one-shot (no device attached at the time), and the locale relaunch.
