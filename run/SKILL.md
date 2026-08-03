---
name: run
description: >
  Build and run any iOS, Android, or web prototype project. For mobile, runs on simulator,
  emulator, or physical device — auto-detects project type, scheme, bundle ID, package name,
  and main activity. Works with Xcode projects (xcodeproj/xcworkspace), xcodegen (project.yml),
  Gradle (gradlew), CocoaPods, SPM, and KMP multi-platform repos. For web, serves a directory
  containing an HTML entry point via a local HTTP server and opens it in the browser
  (handles JSX/Babel-in-browser prototypes that fail under file://).
  Trigger on: "run the app", "build and run", "launch on simulator", "launch on device",
  "install on device", "run on emulator", "run on iPhone", "run on Android",
  "boot simulator and run", "run debug build", "open page", "serve this", "run the html",
  "preview the prototype".
allowed-tools: [xcodebuild, gradle, adb, python3]
---

# Run — Universal Build & Run

Build and run any iOS or Android project. Detect everything dynamically — never hardcode
scheme names, bundle IDs, package names, simulator names, or file paths.

---

## Phase 1 — Parse Arguments

`android` is optional. Parse tokens case-insensitively in any order:

| Token | Meaning | Default |
|---|---|---|
| `ios` / `android` / `web` | Platform | Auto-detect from project files |
| `sim` / `simulator` / `emulator` | Target: simulator/emulator | iOS: simulator; Android: emulator if no device connected |
| `device` / `phone` | Target: physical device | — |
| `debug` / `release` | Build configuration (mobile only) | `debug` |
| Bare integer (e.g. `8080`) | Web server port | First free port in 8000–8999 |
| Anything else in quotes or multi-word | Device/simulator name OR HTML entry filename | iOS: latest iPhone sim; Android: first available; Web: auto-detected entry |

Examples:
- `/run` — auto-detect platform, run on simulator/emulator/browser
- `/run ios device` — iOS on physical device, debug
- `/run android` — Android on emulator, debug
- `/run ios sim "iPhone 16 Pro"` — iOS on named simulator
- `/run android release` — Android release build on emulator/device
- `/run web` — serve the current directory and open the detected HTML entry
- `/run web 8080` — serve on port 8080
- `/run web index.html` — serve and open a specific entry file

---

## Phase 2 — Project Discovery

### Step 2.1 — Find project root

Walk up from the current working directory to find the project root:

```bash
dir="$PWD"
while [ "$dir" != "/" ]; do
  ls "$dir"/*.xcworkspace "$dir"/*.xcodeproj "$dir"/project.yml 2>/dev/null && break
  [ -f "$dir/gradlew" ] && break
  [ -d "$dir/.git" ] && break
  dir="$(dirname "$dir")"
done
echo "Project root: $dir"
```

Store as `$PROJECT_ROOT`.

### Step 2.2 — Detect platform(s)

If the user did not specify a platform, detect from project files:

```bash
HAS_IOS=false
HAS_ANDROID=false
HAS_WEB=false

# iOS markers (check root and common subdirectories)
find "$PROJECT_ROOT" -maxdepth 2 \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "project.yml" \) -not -path "*/.*" 2>/dev/null | head -1 && HAS_IOS=true

# Android markers
[ -f "$PROJECT_ROOT/gradlew" ] && HAS_ANDROID=true

# Web markers — any .html in the cwd or PROJECT_ROOT (excluding hidden / node_modules)
find "$PROJECT_ROOT" -maxdepth 2 -name "*.html" -not -path "*/node_modules/*" -not -path "*/.*" 2>/dev/null | head -1 && HAS_WEB=true
```

Platform precedence when multiple are detected:
- Native (iOS/Android) takes precedence over web — web is the fallback when no mobile project files are present
- If both iOS and Android exist (KMP/multi-platform): cwd inside `iOSApp/`/`ios/`/`iosApp/` → iOS; inside `androidApp/`/`app/` → Android; otherwise ask
- If user explicitly passed `web`, use web even when mobile project files are present

### Step 2.3 — iOS Project Discovery

#### 2.3.1 — Find the Xcode project file

```bash
# Search root and common iOS subdirectory names
for subdir in "$PROJECT_ROOT" "$PROJECT_ROOT"/iOSApp "$PROJECT_ROOT"/ios "$PROJECT_ROOT"/iosApp; do
  # Prefer .xcworkspace (required for CocoaPods)
  if ls "$subdir"/*.xcworkspace 2>/dev/null | head -1; then
    IOS_DIR="$subdir"
    XCODE_FILE="$(ls "$subdir"/*.xcworkspace 2>/dev/null | head -1)"
    XCODE_FLAG="-workspace"
    break
  elif ls "$subdir"/*.xcodeproj 2>/dev/null | head -1; then
    IOS_DIR="$subdir"
    XCODE_FILE="$(ls "$subdir"/*.xcodeproj 2>/dev/null | head -1)"
    XCODE_FLAG="-project"
    break
  fi
done
```

#### 2.3.2 — Detect scheme and bundle ID

**Path A — xcodegen project (project.yml exists):**

Read `project.yml` directly and extract:
- **Scheme**: The first key under `schemes:` that is NOT a test or screenshot scheme
- **Bundle ID**: The `PRODUCT_BUNDLE_IDENTIFIER` value under the target with `type: application`

This is preferred because it is instant — no SPM package resolution.

**Path B — Standard Xcode project (no project.yml):**

```bash
xcodebuild -list $XCODE_FLAG "$XCODE_FILE" 2>/dev/null
```

Pick the app scheme: exclude names ending with `Tests`, `UITests`, or containing `Widget`, `Screenshot`, `Watch`, `Extension`, `Clip`. Prefer the scheme matching the project/workspace filename.

Then extract bundle ID:

```bash
xcodebuild -showBuildSettings \
  $XCODE_FLAG "$XCODE_FILE" \
  -scheme "$SCHEME" \
  2>/dev/null | grep "PRODUCT_BUNDLE_IDENTIFIER" | head -1 | awk '{print $NF}'
```

Store: `$SCHEME`, `$BUNDLE_ID`, `$XCODE_FILE`, `$XCODE_FLAG`, `$IOS_DIR`

### Step 2.4 — Android Project Discovery

#### 2.4.1 — Find Gradle project and app module

```bash
GRADLE_ROOT="$PROJECT_ROOT"
[ -x "$GRADLE_ROOT/gradlew" ] || chmod +x "$GRADLE_ROOT/gradlew"

# Detect app module from settings.gradle.kts or settings.gradle
SETTINGS_FILE=""
[ -f "$GRADLE_ROOT/settings.gradle.kts" ] && SETTINGS_FILE="$GRADLE_ROOT/settings.gradle.kts"
[ -f "$GRADLE_ROOT/settings.gradle" ] && SETTINGS_FILE="$GRADLE_ROOT/settings.gradle"
grep 'include' "$SETTINGS_FILE"
```

Identify the Android app module — prefer `:androidApp` (KMP) or `:app` (standard). Verify by checking which module's `build.gradle.kts` contains `com.android.application`.

#### 2.4.2 — Extract package name

```bash
grep -E "applicationId|namespace" "$GRADLE_ROOT/$APP_MODULE/build.gradle.kts"
```

Use `applicationId` value; fall back to `namespace` if not set.

#### 2.4.3 — Extract main activity

```bash
MANIFEST="$GRADLE_ROOT/$APP_MODULE/src/main/AndroidManifest.xml"
grep -B5 "android.intent.category.LAUNCHER" "$MANIFEST"
```

Parse the `android:name` from the LAUNCHER `<activity>`. If relative (`.MainActivity`), prepend the package name.

Store: `$APP_MODULE`, `$PACKAGE_NAME`, `$MAIN_ACTIVITY`, `$GRADLE_ROOT`

### Step 2.5 — Web Project Discovery

Run only when platform is web.

#### 2.5.1 — Choose serve directory

Default to the current working directory (`$PWD`). This is what the user expects when they say "open page" or "run the html" from a folder containing the file.

#### 2.5.2 — Detect HTML entry file

If the user passed an explicit filename argument, use it. Otherwise:

```bash
# Prefer common entry names, then fall back to any .html in the directory
for candidate in index.html main.html app.html; do
  [ -f "$SERVE_DIR/$candidate" ] && ENTRY="$candidate" && break
done
if [ -z "$ENTRY" ]; then
  # Take the only .html if there's exactly one; otherwise list and ask
  HTML_COUNT=$(ls "$SERVE_DIR"/*.html 2>/dev/null | wc -l | tr -d ' ')
  if [ "$HTML_COUNT" = "1" ]; then
    ENTRY=$(basename "$(ls "$SERVE_DIR"/*.html)")
  elif [ "$HTML_COUNT" -gt 1 ]; then
    ls "$SERVE_DIR"/*.html
  fi
fi
```

If multiple `.html` files exist and no entry was specified, present the list and ask which to open. Do not guess.

#### 2.5.3 — Pick a port

If the user passed a numeric port, use it. Otherwise pick the first free port starting at 8000:

```bash
PORT=8000
while lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; do
  PORT=$((PORT + 1))
  [ "$PORT" -gt 8999 ] && echo "No free port in 8000–8999" && exit 1
done
```

Store: `$SERVE_DIR`, `$ENTRY`, `$PORT`

---

## Phase 3 — Build & Run

### Before executing — Print a summary:

```
## Run: <project-name>
Platform:  iOS / Android
Target:    Simulator (<name>) / Device (<name>)
Config:    Debug / Release
Scheme:    <scheme>           (iOS only)
Bundle ID: <bundle-id>       (iOS only)
Package:   <package-name>    (Android only)
Activity:  <main-activity>   (Android only)
Project:   <path-to-project-file>
```

---

### 3A — iOS Simulator

#### 3A.1 — Select and boot simulator

```bash
xcrun simctl list devices available
```

Selection priority (when no name specified):
1. Latest iPhone Pro Max
2. Latest iPhone Pro
3. Any available iPhone

```bash
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
open -a Simulator
```

#### 3A.2 — Build

```bash
cd "$IOS_DIR"
xcodebuild build \
  $XCODE_FLAG "$XCODE_FILE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -configuration Debug \
  -skipMacroValidation
```

**On build failure:** Show errors and STOP. Do not proceed to install.

#### 3A.3 — Find the built .app

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/$SCHEME-*/Build/Products/Debug-iphonesimulator/*.app" -maxdepth 6 -type d 2>/dev/null | head -1)
```

#### 3A.4 — Install and launch

```bash
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted "$BUNDLE_ID"
```

---

### 3B — iOS Physical Device

#### 3B.1 — List and select device

**Always list all devices first** so the user can see what's available:

```bash
xcrun devicectl list devices 2>&1
```

Display the results as a formatted table showing Name, State (connected/unavailable), and Model. Then:

- If a specific device name was provided in arguments, match it
- Otherwise, **automatically pick the first device with State = `connected`** — no need to ask
- If NO devices are connected: "No physical iOS device connected. Connect a device and try again, or use `/run ios sim`."

**Use the `Identifier` column from `devicectl list devices`** (UUID format) — NOT the UDID from `xctrace`.

#### 3B.2 — Build for device

```bash
cd "$IOS_DIR"
xcodebuild build \
  $XCODE_FLAG "$XCODE_FILE" \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -configuration Debug \
  -skipMacroValidation
```

#### 3B.3 — Find the built .app

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/$SCHEME-*/Build/Products/Debug-iphoneos/*.app" -maxdepth 6 -type d 2>/dev/null | head -1)
```

#### 3B.4 — Install and launch

```bash
xcrun devicectl device install app --device "$UDID" "$APP_PATH"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
```

---

### 3C — Android Emulator

#### 3C.1 — Check for running emulator or boot one

```bash
adb devices | grep -v "List" | grep -v "^$"
```

If no device connected:

```bash
# Try $ANDROID_HOME first, fall back to ~/Library/Android/sdk
EMULATOR_CMD="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
AVD_NAME=$("$EMULATOR_CMD" -list-avds | head -1)
"$EMULATOR_CMD" -avd "$AVD_NAME" &
adb wait-for-device
```

If no AVDs exist: "No Android emulators configured. Create one in Android Studio (Tools > Device Manager) and try again."

#### 3C.2 — Build and install

```bash
cd "$GRADLE_ROOT"
./gradlew ":$APP_MODULE:installDebug"
```

For release: `./gradlew ":$APP_MODULE:installRelease"`

#### 3C.3 — Launch

```bash
adb shell am start -n "$PACKAGE_NAME/$MAIN_ACTIVITY"
```

---

### 3D — Android Physical Device

Same as 3C except:
- Skip emulator boot step
- Verify a physical device is connected (`adb devices` — filter out `emulator-*` serials)
- Use `-s <serial>` for adb commands if multiple devices are connected

---

### 3E — Web Prototype (local HTTP server)

Use when an HTML file needs to be served (rather than opened with `file://`). Required
whenever the page loads other local files via `<script src="…">`, fetch, modules,
JSX/Babel-in-browser, etc., because browsers block those under `file://`.

#### 3E.1 — Reuse an existing server if possible

```bash
if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  # If something is already serving the same dir on this port, just reuse it
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/$ENTRY"
fi
```

If port is in use by an unrelated process, pick the next free port (see 2.5.3).

#### 3E.2 — Start the server in the background

Prefer `python3 -m http.server` (always present on macOS). Fall back to `npx http-server`
or `php -S` if Python is unavailable.

```bash
cd "$SERVE_DIR"
python3 -m http.server "$PORT" >/tmp/run-web-$PORT.log 2>&1 &
disown
sleep 1
```

#### 3E.3 — Verify the entry loads

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://localhost:$PORT/$ENTRY"
```

If the response is not 200, show the server log (`/tmp/run-web-$PORT.log`) and stop.

#### 3E.4 — Open in the browser

```bash
open "http://localhost:$PORT/$ENTRY"   # macOS
# Linux: xdg-open ; Windows: start
```

#### 3E.5 — Tell the user how to stop it

After launching, print:
```
Serving <SERVE_DIR> on http://localhost:<PORT>/<ENTRY>
Stop the server: lsof -ti:<PORT> | xargs kill
```

---

## Error Recovery

| Error | Recovery |
|---|---|
| Build fails with signing errors | Tell user: "Open Xcode, select a team under Signing & Capabilities, then retry." |
| `xcrun simctl install` fails | Ensure simulator is booted: `xcrun simctl boot "$SIM_NAME"` |
| `adb: no devices/emulators found` | Check USB debugging is enabled; for emulator: boot one first |
| `gradlew` permission denied | Run `chmod +x gradlew` |
| `.app` not found in DerivedData | Re-run build without piping output to see full errors |
| `PRODUCT_BUNDLE_IDENTIFIER` contains `$(...)` | Use `xcodebuild -showBuildSettings` which resolves variables |
| `xcodebuild -list` hangs (SPM resolution) | Kill and suggest `xcodegen generate` if `project.yml` exists |
| Web: page renders blank / console shows CORS or "Failed to fetch" for local files | This is exactly why we serve over HTTP — confirm the URL is `http://localhost:<PORT>/<ENTRY>`, not `file://` |
| Web: port already in use | Pick the next free port (Phase 2.5.3) instead of killing the existing process |
| Web: `python3` not installed | Fall back to `npx http-server "$SERVE_DIR" -p "$PORT"` or `php -S localhost:$PORT -t "$SERVE_DIR"` |

## Rules

- NEVER hardcode scheme names, bundle IDs, package names, simulator names, or file paths
- ALWAYS detect values dynamically from the project files in the current directory tree
- Prefer `.xcworkspace` over `.xcodeproj` when both exist (CocoaPods compatibility)
- Prefer parsing `project.yml` over `xcodebuild -list` when available (faster, no SPM resolution)
- Do NOT clean before building unless the user explicitly asks
- Do NOT modify project files, signing settings, or build settings
- Do NOT run `xcodegen generate` automatically — only suggest if build fails with missing-file errors
- If auto-detection finds multiple candidates for any value, present options and ask the user
- On build failure, show error output and STOP — do not proceed to install/launch
- For Android, always `cd` to the directory containing `gradlew` before running Gradle
- For web, never open an HTML file directly with `file://` if it contains `<script src="...">`, fetch, JSX, or modules — always serve over HTTP
- For web, run the server in the background (`&` + `disown`) so the user keeps their terminal, and tell them how to stop it
- After successful launch, print: "App launched successfully on <target>." (mobile) or "Serving on http://localhost:<PORT>/<ENTRY>" (web)

## Phase 4 — Post-launch: "what can I test?"

After a successful **mobile** launch, ALWAYS append a short "What you can test" section to the same response. This helps the user know what surfaces are actually exercised by the build they just got.

Scope it to the **current branch**, not the whole project:

1. Look at `git log --oneline <base>..HEAD` where `<base>` is the merge target (epic branch if on a task branch, else `main`). For each commit on the branch, briefly note what user-visible surface it added or changed.
2. If the branch only contains plumbing (ports, schemas, domain code, build/CI changes), say so explicitly — the user shouldn't hunt for a UI that doesn't exist yet — and list what's testable from the **already-merged** baseline (i.e. the prior phase's surface visible at HEAD).
3. If the project has language / theme / RTL toggles, mention how to flip them when the current branch's changes are language- or layout-sensitive (e.g. iOS simulator language flag, Android emulator settings).
4. Group by feature area, bulleted, no speculation about future tasks. If a surface lands in a later task per the project's plan, mention "lands in Task N" once — don't enumerate the future.

Skip Phase 4 if:
- The build failed (you already stopped per the Rules above).
- The platform was `web` (this section is mobile-app-specific).
- The user explicitly told you to skip post-launch notes (e.g. `/run quiet`).
