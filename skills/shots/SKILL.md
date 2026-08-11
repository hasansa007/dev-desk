---
name: shots
description: >
  CAPTURES screens from the running app — iOS, Android and web — and optionally post-processes them
  into App Store / Play Store dimensions. A door into `dev:launch`: it reuses that skill's project
  discovery and its "reuse a server that is already up, start nothing" rule, then captures.
  Takes the CURRENT screen by default (`simctl io` · `adb screencap` · Chrome DevTools MCP), and
  drives the project's OWN screen-walking automation when it has one (a screenshot UITest scheme,
  a fastlane Snapfile, a Playwright/Cypress spec) for a full ordered, per-locale set.
  Store mode captures natively on the LARGEST device available, then DERIVES every other iPhone
  App Store slot from that one image — scale to the target width and crop the few pixels of height
  that overshoot, never `sips -z`, which stretches. A listing exposes slots the skill cannot see,
  so it covers them all rather than guessing; sources are never overwritten and derived sizes go in
  their own per-slot directory.
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
| `store` | Capture native, then derive **every** iPhone slot in Phase 5's table, locale-sorted | plain capture |
| `flow` / `current` | Force the driven suite / force a single shot | auto (Phase 4) |
| `dry` | Report the plan, capture nothing | capture |
| A path | Output directory | `./shots/<platform>/` |

## Phase 2 — Discover — *point, do not restate*

Read `skills/launch/SKILL.md` and use unchanged:

| From `dev:launch` | For |
|---|---|
| **2.0** | the three resolution rules — **this skill is where two of the three were found**, so it must not re-learn them |
| **2.1** | `$PROJECT_ROOT` — worktree-safe (`git rev-parse --show-toplevel` first) |
| **2.2** | which platforms exist, and its precedence rules |
| **2.3.0** | **resolving the Xcode toolchain** — `xcrun simctl` fails outright when `xcode-select` points at Command Line Tools, even with Xcode installed |
| **2.3 / 2.4** | iOS scheme + bundle ID · Android package + activity |
| **2.2a** | the project's DECLARED entry points — `.vscode`, `.xcscheme`, `.idea/runConfigurations` |
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

## Phase 5 — Store mode: capture the largest natively, DERIVE the rest

**Capture on the biggest device the toolchain offers, then derive every other iPhone slot from that
one image.** One native capture, one derivation per slot, no second run of the app.

**A listing has SLOTS, not a size.** This is the correction that makes the phase automatic: an
"older" size is not a retired size, it is a *different slot*, and the one your listing exposes is
not something you can infer from the device you own. Producing only the size you captured is
therefore a coin flip on whether it uploads at all.

| Slot | Accepted (portrait) | Native on |
|---|---|---|
| 6.9" | `1320×2868` · `1290×2796` | iPhone 17 / 16 Pro Max — **capture here** |
| 6.5" | `1284×2778` · `1242×2688` | 12–14 Pro Max, XS Max — no longer shipped as simulators |
| 6.1" | `1206×2622` · `1179×2556` | the non-Max Pro of the same years |

Landscape is each pair transposed. The table is a **starting point that goes stale** — it is Apple's
list, not yours, so when a slot rejects an upload, believe the slot and add the row.

### Derive by scale-then-crop — never `-z`

```bash
# 1. proportional scale to the target WIDTH — aspect preserved exactly, nothing stretched
sips --resampleWidth "$W" "$SRC" --out "$OUT/$name"
# 2. centred crop of the few pixels of height that overshoot. `-c` takes HEIGHT then WIDTH
sips -c "$H" "$W" "$OUT/$name"
```

Neighbouring iPhone slots differ in aspect by well under 1%, so step 2 removes a handful of rows —
6 pixels top and bottom on a 2790px image, invisible. `-z H W` would instead force both dimensions
and stretch the whole frame by that same fraction. **The 1% aspect check still applies**: if the
delta is larger than that, the two slots are not neighbours and a crop would eat content — stop and
say so.

- **Never overwrite the source.** Derive into a directory named for the slot
  (`appstore-6.5-1284x2778/`), so which file is native and which is derived is legible without
  opening either. `sips` with no `--out` edits in place and the original is unrecoverable.
- **Derive DOWNWARD only.** Upscaling invents detail and softens type. If the required slot is
  bigger than anything you can capture, say so — do not quietly enlarge.
- **Verify the output dimensions after writing**, per slot. A `sips` that silently no-ops leaves a
  file of the wrong size with a confident name on it.

Then sort into locale folders and preserve ordering — App Store Connect displays by filename, which
is exactly why the driven suites name tests `test01_…`, `test06_…`. Keep those prefixes.

## Phase 6 — Report, then tear down what *you* started

```
## shots: <project>
iOS sim (iPhone 17 Pro Max, 1320×2868 native)  driven suite, 6 screens × ar,en  -> shots/ios/
  derived 6.5"  1284×2778  scale+crop 12px  -> shots/ios/appstore-6.5-1284x2778/
  derived 6.1"  1206×2622  scale+crop  9px  -> shots/ios/appstore-6.1-1206x2622/
Android (emulator-5554)                        current screen ×1                -> shots/android/
Web                                            reused :3007, started nothing    -> shots/web/

project.yml: screenshot scheme enabled (diff printed above), xcodegen re-run
Teardown: simulator left booted (yours) · dev server untouched (already up)
```

**Report the derivation, never just the count.** Which size is native and which was resampled is
the one thing the files cannot say for themselves, and it decides which set to upload when a slot
complains.

**Stop only what this run started**, by delegating to `dev:launch-kill`. Anything that was already
up is reported as untouched and never stopped. An unreported leftover is the process still running
tomorrow.

## Never

- **Restart a running app to photograph it.** Reuse it (Phase 3 / `launch` 3F.1).
- **Overwrite a source image.** Derived sizes go in their own per-slot directory.
- **Resize with `-z`**, which forces both dimensions and stretches. Scale to the width, crop the
  height (Phase 5) — and only when the aspect delta is under 1%.
- **Upscale to reach a slot.** Derive downward from the largest native capture, or say you cannot.
- **Treat Phase 5's size table as authoritative.** It is Apple's list, it goes stale, and this file
  cannot know when. A slot that rejects an upload outranks the table — believe it, add the row.
  (This replaces the older *"never hard-code store dimensions"*, which forbade writing the sizes
  down at all and so left every run to rediscover them, one rejected upload at a time.)
- **Capture with an implicit target** when several devices are connected.
- **Claim a screen was captured without checking the file exists and is non-zero** — and, for a
  derived file, without re-reading its dimensions.

## Known limits

| | |
|---|---|
| iOS **device** current-screen capture | No `simctl io` equivalent; needs the UITest suite. Simulator only for one-shot |
| Android locale switching | No clean per-launch flag like iOS; needs a device settings change. Driven suites handle it, one-shot does not |
| Store-size validation | Offline, the skill cannot know Apple's *current* accepted list, nor **which slots a given listing exposes** — that is per-app and lives in App Store Connect. Phase 5 answers it by covering every iPhone slot in the table rather than guessing which one is wanted; a slot outside the table still needs one rejected upload to discover |
| Deriving across device *families* | Only iPhone slots are derived. iPad aspect ratios are nowhere near iPhone's, so the under-1% crop rule refuses them by design — iPad needs its own native capture |
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
   **Half wrong, corrected 2026-08-11 — see the third entry.** The number was hard-coded, which is a
   real fault. But it was never a *dead* size: 1284 × 2778 is the 6.5" slot, still accepted, and
   reading this line as "that size is obsolete" is what later justified deleting the resize step
   outright and shipping a set that only fitted one slot.
4. Ordering was lost, though the suite's `test01_…` prefixes existed precisely to preserve it.

Fixed structurally rather than patched: capture natively on a correctly-sized device, and the resize
step — with all three of its bugs — stops existing. **Superseded 2026-08-11:** a native capture is
still the right *source*, but it cannot be the only output, because no shipping simulator has a
native 6.5" resolution.

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

**2026-08-11 — "pick the device, do not resize" was right about the METHOD and wrong about the
OUTPUT.** A full five-screen set was captured natively at 1320 × 2868, verified frame by frame, and
handed over. App Store Connect rejected all five:

> Screenshots dimensions should be: 1242 × 2688px, 2688 × 1242px, 1284 × 2778px or 2778 × 1284px

Those four are the **6.5" slot**, and the listing exposed that slot rather than 6.9". Three things
follow, and they are why Phase 5 was rewritten rather than amended:

- **A listing has slots, and the skill cannot see them.** Which one a given app exposes lives in App
  Store Connect. Producing only the size you happened to capture is a coin flip, and the phase had
  no answer for losing it — the previous text called resizing a fallback "only for images that
  cannot be re-captured", which reads as *this will not happen to you*.
- **Re-capturing was not available.** Xcode 27 ships iPhone 17-series and Air only; nothing with a
  native 6.5" resolution exists to boot. The escape hatch the old phase assumed was gone.
- **The entry above had told me the size was obsolete**, so deleting the resize step felt like
  removing dead weight rather than removing the only path to a second slot. A scar that overstates
  its lesson causes the next incident.

The fix is a **derivation**, not a resize: scale to the target width, crop the ≤12px of height that
overshoots. Aspect is preserved exactly, no `-z`, source untouched, output in a per-slot directory.
Measured on the real files — 1320 → 1284 gives 2790, so 6 pixels come off the top and 6 off the
bottom of a 2868px image. `-z 2778 1284` on the same source stretches the entire frame by 0.42%.

**Deriving is now the default for iPhone, not a fallback**, because covering every slot costs one
`sips` pair per size and losing the coin flip costs a rejected upload and a round trip.

**Proven 2026-08-11:** the iPhone derivation — five frames scaled 1320→1284 and cropped to
1284 × 2778, dimensions re-read per file, sources intact at 1320 × 2868, no content clipped.

**Undated, therefore unproven:** every driven-flow path (iOS UITest, Android suite, Playwright), the
Android one-shot (no device attached at the time), the locale relaunch, and the **6.1" row** of
Phase 5's table — only the 6.5" derivation has been run against a real listing.
