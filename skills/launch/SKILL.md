---
name: launch
description: >
  COMPILES and launches a real app — an Xcode or Gradle BUILD onto a simulator, emulator or
  physical device, or a framework web app on its own dev server. Not a generic process starter.
  MOBILE: auto-detects scheme, bundle ID, package name and main activity, then builds, installs
  and launches — Xcode (xcodeproj/xcworkspace), xcodegen (project.yml), Gradle (gradlew),
  CocoaPods, SPM, KMP multi-platform.
  WEB APP (Next.js, Vite, Astro, SvelteKit, CRA): checks the port FIRST and reuses a dev server
  that is already listening — opening the browser and starting nothing, never killing the
  developer's own process — otherwise launches it via the project's OWN script
  (.vscode/dev.sh, bin/dev, scripts/dev, a Makefile target) in preference to a bare `npm run dev`,
  because such a wrapper usually starts a database or injects env that the bare command skips.
  STATIC PROTOTYPE: serves the directory over local HTTP (for JSX/Babel-in-browser pages that
  fail under file://).
  Trigger on: "run the app", "build and run", "launch on simulator", "launch on device",
  "install on device", "run on emulator", "run on iPhone", "run on Android", "boot the simulator",
  "run a debug build", "run a release build", "start the dev server", "open the app",
  "serve this", "run the html", "preview the prototype".
allowed-tools: [git, xcodebuild, xcrun, xcodegen, gradle, adb, lsof, nc, curl, open, python3]
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
- `/dev:launch` — auto-detect platform, run on simulator/emulator/browser
- `/dev:launch ios device` — iOS on physical device, debug
- `/dev:launch android` — Android on emulator, debug
- `/dev:launch ios sim "iPhone 16 Pro"` — iOS on named simulator
- `/dev:launch android release` — Android release build on emulator/device
- `/dev:launch web` — a framework app: reuse its dev server if up, else start it; a static folder: serve it
- `/dev:launch web 8080` — serve on port 8080
- `/dev:launch web index.html` — serve and open a specific entry file

---

## Phase 2 — Project Discovery

### Step 2.0 — Three resolution rules — read before any detector

Every detector below, and every tool that points at this phase, obeys these. They exist because the
same failure happened three times in one day, in three unrelated places.

**1. Installed ≠ reachable. Check all three hiding places before reporting a capability absent.**

| | Where it hides | Miss looks like |
|---|---|---|
| `PATH` | the obvious one | — |
| The SDK's canonical location | `${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/` | "Android unavailable" |
| The **toolchain selector** | `xcode-select -p` pointing at Command Line Tools while Xcode sits installed | "no simulators" |

**2. Never report absence without printing where you looked.** *"iOS unavailable"* is a claim; it
needs its search path attached. This is the rule with teeth — a false negative survives only while
it is unexamined, and a visibly empty search path is self-refuting. **These failures do not error,
they answer** — and a confident wrong answer gets believed in a way a stack trace never does.

This rule covers the **empty** result only. Its other half — a **non-empty** result that answers a
narrower question than you asked, and so gets reported as the broader one — is
`shared/entry.md` § *A result is not a claim*. Same failure mode, one file, no copy of it here.

**3. Prefer a DECLARATION over a guess.** When the project states a fact, read the statement rather
than inferring it from names:

| Guess | Declaration |
|---|---|
| `dev.sh`, `bin/dev`, `scripts/dev*` | `.vscode/launch.json` · `.xcscheme` · `.idea/runConfigurations` (2.2a) |
| a hardcoded store dimension | the device's native resolution (`dev:shots` Phase 5) |
| `grep '#[0-9]+'` over an epic body | its `- [ ] #N` task list (`dev:issues` 4.1) |
| `[ -d "$dir/.git" ]` | `git rev-parse --show-toplevel` (2.1) |

> **2026-08-05 — four instances, one root.** `adb` present but off `PATH`; `simctl` present but not
> selected; a run script found by filename while `launch.json` named it outright; an epic child
> invented by a bare `#N` grep. Each encoded a *correct principle* as a *fragile lookup*, and each
> failed as a **false negative rather than an error**. The `adb` fix was written into one tool while
> this file had carried the same fallback for the emulator 200 lines away — neither knew about the
> other. **That** is why these rules sit here, at the top of the phase every tool points at, instead
> of being re-learned per skill.

### Step 2.1 — Find project root

Walk up from the current working directory to find the project root:

```bash
# Git first — it is the only form that gets WORKTREES right.
dir="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$dir" ]; then
  dir="$PWD"
  while [ "$dir" != "/" ]; do
    ls "$dir"/*.xcworkspace "$dir"/*.xcodeproj "$dir"/project.yml 2>/dev/null && break
    [ -f "$dir/gradlew" ] && break
    [ -e "$dir/.git" ] && break        # -e, not -d: in a worktree .git is a FILE
    dir="$(dirname "$dir")"
  done
fi
echo "Project root: $dir"
```

**2026-08-05 — `-d "$dir/.git"` resolved `$PROJECT_ROOT` to `/`.** In a git worktree `.git` is a
*file*, not a directory, so the `-d` test never fires and the loop never stops: measured from
a real worktree under `~/.superconductor/worktrees/` it climbed through `~/`, through
`/Users/`, and returned **`/`**. Every detector below then searches the filesystem root — and
`dev:launch-kill`, which reads this section, would have treated *every process on the machine* as
owned by the project. `git rev-parse --show-toplevel` returns the worktree's own path, which is why
it goes first and why the fallback tests `-e`.

Store as `$PROJECT_ROOT`. **It is a boundary, not a hint** — every detector below searches inside it
and nowhere else. Additional working directories, sibling repos and anything else this session
happens to be able to read are NOT this project.

### Step 2.2 — Detect platform(s)

If the user did not specify a platform, detect from project files:

```bash
HAS_IOS=false
HAS_ANDROID=false
HAS_WEBAPP=false
HAS_WEB=false

# iOS markers (check root and common subdirectories)
find "$PROJECT_ROOT" -maxdepth 2 \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "project.yml" \) -not -path "*/.*" 2>/dev/null | head -1 && HAS_IOS=true

# Android markers
[ -f "$PROJECT_ROOT/gradlew" ] && HAS_ANDROID=true

# Framework web APP — a package.json carrying a dev script (root or one level down: web/, app/, frontend/)
find "$PROJECT_ROOT" -maxdepth 2 -name package.json -not -path "*/node_modules/*" -not -path "*/.*" \
  -exec grep -l '"dev"' {} \; 2>/dev/null | head -1 && HAS_WEBAPP=true

# Static web prototype — a loose .html (excluding hidden / node_modules)
find "$PROJECT_ROOT" -maxdepth 2 -name "*.html" -not -path "*/node_modules/*" -not -path "*/.*" 2>/dev/null | head -1 && HAS_WEB=true
```

Platform precedence when multiple are detected:
- Native (iOS/Android) takes precedence over anything web
- **`HAS_WEBAPP` beats `HAS_WEB`.** A framework app needs its dev server (3F); a static file server
  (3E) would serve the source directory and render nothing useful. Repos trip both detectors all the
  time — a Next.js project with a stray `public/preview.html` — and choosing static there is the
  silent-wrong-answer case
- If both iOS and Android exist (KMP/multi-platform): cwd inside `iOSApp/`/`ios/`/`iosApp/` → iOS; inside `androidApp/`/`app/` → Android; otherwise ask
- **If NOTHING is detected in `$PROJECT_ROOT`, say so and STOP.** Two wrong answers live here, and
  the second one is the quiet one:
  - Never fall back to "serve the directory" — an empty static server returns 200 on a directory
    listing and looks like success
  - **Never reach into another repo.** Observed 2026-08-05: `/dev:launch` run from the dev-skill
    repo found no app there and silently continued discovery in ANOTHER repo — a different
    project, reachable only because it was an additional working directory — getting as far as
    reading its launch script before anyone noticed the repo had changed. A session can reach many
    repos; exactly one of them is `$PROJECT_ROOT`. When another obviously holds the app, that is a
    sentence to say, not a licence to launch: *"No app in this repo. `<other-repo>/web` has one
    — launch that instead?"* The user answering "yes" is what makes it the project; proximity is not
  This is not the web path's problem. A repo of skills, a docs repo, a monorepo tool directory —
  any of them can be `$PWD`, and the iOS and Android detectors fail the same way
- If user explicitly passed `web`, use web even when mobile project files are present

### Step 2.2a — Read the project's DECLARED entry points — EVERY platform

Rule 3 of Step 2.0, implemented. Run this for **whatever 2.2 detected** — it is not a web step.
Each ecosystem declares what is runnable in a different file, and the mistake is assuming the
editor you use is the one the project was configured in:

| Platform | The declaration | Notes |
|---|---|---|
| Any | `.vscode/launch.json` · `.vscode/tasks.json` | JSONC — see the parser below |
| iOS | `*.xcodeproj/xcshareddata/xcschemes/*.xcscheme` | the **shared**, committed schemes |
| iOS (xcodegen) | `project.yml` → `schemes:` | already read at 2.3.2 path A |
| Android | `.idea/runConfigurations/*.xml` | Android Studio's equivalent of `launch.json` |
| Android | `settings.gradle*`, `build.gradle*` | already read at 2.4 |

> **2026-08-05 — this step was written web-only and had to be moved.** It first lived under Step 2.6
> (*"Run only when `HAS_WEBAPP`"*), so 2.0's "prefer a declaration over a guess" applied to exactly
> one of three platforms. Re-running it for mobile would not have fixed it either: **not one mobile
> repo checked had a `.vscode/` directory** — mobile is configured in Xcode and Android Studio, so
> its declarations live in `.xcscheme` and `.idea/runConfigurations`. The rule was portable; the
> implementation was shaped like the platform it was discovered on.

**Two iOS-specific traps this exposes:**

- **Unshared schemes are invisible.** Of three mobile repos checked, one had **1130** shared
  `.xcscheme` files and two had **zero** — not because they lack schemes, but because theirs live in
  `xcuserdata/`, which is user-local and usually gitignored. So `xcodebuild -list` can come back
  thin or empty on a fresh clone. **Report that as "no shared schemes", never as "no schemes"** —
  they are different facts and only one of them is the project's.
  *(That count first read "21" here — a `-maxdepth 4` artifact of my own search. Both failure
  directions are live in one bullet: a capped search under-reporting, and gitignored state
  disappearing entirely.)*
- **Enumerating schemes is a declaration; picking one is a guess.** 2.3.2's exclusion list
  (`Tests`, `UITests`, `Widget`, `Screenshot`, …) is a heuristic sitting on top of good data, and it
  degrades as the list grows — with 21 schemes, "the one that isn't a test" is not a unique answer.
  When more than one survives the filter, **present them and ask** (Rules).

```bash
python3 - "$PROJECT_ROOT/.vscode" <<'PY'
import json, re, sys, pathlib
def strip_jsonc(s):                       # comments + trailing commas, STRING-AWARE
    out=[]; i=0; n=len(s); instr=False; esc=False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': instr=False
            i+=1; continue
        if c=='"': instr=True; out.append(c); i+=1; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            while i<n and s[i]!='\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'): i+=1
            i+=2; continue
        out.append(c); i+=1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
d = pathlib.Path(sys.argv[1])
for f, key, name in (("launch.json","configurations","name"), ("tasks.json","tasks","label")):
    p = d/f
    if not p.exists(): continue
    for e in json.loads(strip_jsonc(p.read_text())).get(key, []):
        cmd = e.get("command") or e.get("program") or e.get("runtimeExecutable") or ""
        print(f"{f}\t{e.get(name,'?')}\t{cmd}")
PY
```

**These files are JSONC, not JSON.** `json.loads` fails outright — comments and trailing commas are
both legal. And a naive `s.replace('//','')` corrupts every `http://` in the file, which is how the
open-in-browser entry gets silently mangled. The strip above is string-aware for exactly that
reason. **If parsing fails, fall through to filename guessing and say so** (Rule 2) — never guess at
the contents of a file you could not read.

Then choose:

- **Pick the entry whose name says run** — `run`, `dev`, `start`, `▶`. If several match they are
  usually *variants*, not duplicates: one injecting remote env, one using a local `.env`.
  **Present them and ask.** Picking silently is how you boot the differently-configured app.
- **Record the stop entries** (`stop`, `⏹`) for `dev:launch-kill`, which otherwise guesses that
  filename too.
- **Never auto-run a destructive entry.** `--wipe`, `reset`, `db reset`, `clean` sit in these files
  beside the run entries — an editor list is a menu, not a queue. Name them; run none.
- **`tasks.json` also declares the build/verify command** (`verify: build`, `check`). Prefer it over
  a guessed `npm run build` wherever a pre-PR build is needed.
- **A declared command can still be WRONG.** Verified 2026-08-05: a repo's default build task
  (`isDefault: true`, i.e. Cmd+Shift+B) ran the app through the remote-env wrapper with **none** of
  the overrides its own launch script applies — pointing localhost at the production database and
  live payment credentials. A declaration tells you what the project *says*; it does not certify it.
  Prefer it over a guess, then still read it.

### Step 2.3 — iOS Project Discovery

#### 2.3.0 — Resolve the Xcode toolchain FIRST

```bash
if ! xcrun simctl help >/dev/null 2>&1; then
  for x in /Applications/Xcode*.app; do
    [ -x "$x/Contents/Developer/usr/bin/simctl" ] && export DEVELOPER_DIR="$x/Contents/Developer" && break
  done
fi
xcrun simctl help >/dev/null 2>&1 || echo "No full Xcode found — only Command Line Tools."
```

**2026-08-05 — `xcrun simctl` failed on a machine with Xcode installed.** `xcode-select -p` pointed
at `/Library/Developer/CommandLineTools`, which ships no `simctl`, while
`/Applications/Xcode-27.0.0-Beta.3.app` sat there fully working. Every iOS step below — list, boot,
install, launch — dies with *"unable to find utility simctl"*, and the honest-looking readings of
that are all wrong: "no simulators", "iOS unavailable", "not a Mac with Xcode". It is a **false
negative on a fully-equipped machine**, which is worse than an error.

`DEVELOPER_DIR` is used deliberately instead of `sudo xcode-select -s`: it fixes this run without
sudo and without changing global state the developer did not ask you to change.

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

**Path 0 — a scheme NAMED by 2.2a wins outright.** If a shared `.xcscheme`, a `.vscode` entry or an
`.idea/runConfigurations` entry names the scheme to run, use it and skip the heuristics below. That
is the project stating the answer; A and B are two ways of inferring it.

> **2026-08-05 — 2.2a had no consumer here.** The step was made platform-neutral, and then only the
> web path (2.6.2) actually read its output — iOS and Android went on inferring while the
> declarations sat unused. A rule stated generally and consumed narrowly is *worse* than one honestly
> scoped, because it looks fixed. If 2.2a returns nothing for iOS, fall through to A/B and say so.

> **Path 0 is also the fast path, by three orders of magnitude.** Measured the same day on the
> 1130-scheme project: reading the declarations took **~4.2 s**, while `xcodebuild -list` — Path B —
> **never returned**, hitting a 120 s alarm. That is this file's own `xcodebuild -list hangs (SPM
> resolution)` recovery row, reproduced. Preferring the declaration is not only more correct here,
> it is the difference between four seconds and a hang.

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

**Exclude dependency schemes first** (`Pods/`, `Carthage/`, `.build/`, `DerivedData/`) — CocoaPods
and SPM generate one per dependency and none of them is the app.

**If 2–10 schemes survive, present them and ASK. Above that, do NOT list — say the count and require
either 2.2a's declaration or an explicit scheme argument.**

> **2026-08-05, measured.** A real project carried **1130** shared schemes, and the exclusion filter
> (`Tests`, `UITests`, `Widget`, `Screenshot`, `Watch`, `Extension`, `Clip`) left **870** survivors.
> At that scale the heuristic is not weak, it is meaningless — and so is "present them and ask",
> because 870 options is not a question anyone can answer. My own first count of this repo said
> "21": that was a `-maxdepth 4` artifact, and the truncated number made the problem look survivable.
> **A capped search that reports its capped result as the total is the same false-negative shape as
> the rest of Step 2.0.** Only a declaration resolves this one.

**If `xcodebuild -list` returns few or no schemes, say "no SHARED schemes" — never "no schemes."**
Unshared schemes live in `xcuserdata/`, which is user-local and usually gitignored, so a fresh clone
legitimately shows none while the project has plenty. Two of three repos checked that day reported
zero for exactly that reason. The two statements are different facts and only one is about the
project (Step 2.0, rule 2).

Then extract bundle ID:

```bash
xcodebuild -showBuildSettings \
  $XCODE_FLAG "$XCODE_FILE" \
  -scheme "$SCHEME" \
  2>/dev/null | grep "PRODUCT_BUNDLE_IDENTIFIER" | head -1 | awk '{print $NF}'
```

Store: `$SCHEME`, `$BUNDLE_ID`, `$XCODE_FILE`, `$XCODE_FLAG`, `$IOS_DIR`

### Step 2.4 — Android Project Discovery

#### 2.4.0 — A run configuration NAMED by 2.2a wins outright

`.idea/runConfigurations/*.xml` is Android Studio's `launch.json` — it declares the module, and often
the launch activity and extra flags, that the Run button uses:

```bash
find "$PROJECT_ROOT/.idea/runConfigurations" -name '*.xml' 2>/dev/null | while read -r f; do
  grep -oE 'name="[^"]+"|MODULE_NAME[^/]*value="[^"]+"|ACTIVITY_CLASS[^/]*value="[^"]+"' "$f"
done
```

Use it when present and skip the inference in 2.4.1–2.4.3; fall through to them when it is absent,
and **say which happened**. The grep-the-manifest path below reconstructs by hand what this file
already states — and it silently picks the *first* LAUNCHER activity when a manifest declares
several (flavors, a debug entry point), where the run configuration names the intended one.

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

### Step 2.6 — Framework App Discovery

Run only when `HAS_WEBAPP`.

#### 2.6.1 — Find the app directory and its dev script

```bash
APP_JSON=$(find "$PROJECT_ROOT" -maxdepth 2 -name package.json -not -path "*/node_modules/*" -not -path "*/.*" \
  -exec grep -l '"dev"' {} \; 2>/dev/null | head -1)
APP_DIR=$(dirname "$APP_JSON")
DEV_SCRIPT=$(node -p "require('$APP_JSON').scripts.dev" 2>/dev/null)
echo "$APP_DIR — dev: $DEV_SCRIPT"
```

#### 2.6.2 — Find the LAUNCH PATH — prefer the project's own script

**Do not reach for `npm run dev` first.** Many repos wrap it in a script that does work the bare
command skips — starting a local database, injecting env, linking a deploy CLI, freeing the port.
Running the bare command instead boots a *differently configured* app that looks fine and behaves
subtly wrong. Check in this order and use the first that exists:

| Order | Source | Look for |
|---|---|---|
| 1 | **The project's DECLARED entry points** | read at **2.2a** — all platforms, not just this one |
| 2 | **A project launch script** | `.vscode/dev.sh`, `bin/dev`, `scripts/dev*`, `dev.sh`, a `dev`/`start` target in `Makefile`/`Justfile` |
| 3 | **A documented command** | `CLAUDE.md`, `README.md`, `CONTRIBUTING.md` — a "run locally" / "development" section |
| 4 | **The package.json script** | `<pm> run dev`, package manager from the lockfile: `package-lock.json`→npm · `pnpm-lock.yaml`→pnpm · `yarn.lock`→yarn · `bun.lockb`→bun |

**Read the script before running it** — it tells you the port, the prerequisites (Docker, a local
database), and whether it opens a browser itself. If it already opens one, do not open a second.

#### 2.6.2a — Declared entry points

Moved to **Step 2.2a**, which runs for every platform. It is not a web step: the same rule
covers `.xcscheme` files and `.idea/runConfigurations`. Do not re-implement it here.

#### 2.6.3 — Resolve the port

From the dev script's own flags first (`-p 3007`, `--port 5173`, `${PORT:-3007}`), then the
launch script, then framework defaults: Next 3000 · Vite 5173 · CRA/Remix 3000 · Astro 4321 ·
SvelteKit 5173. **Never assume — a wrong port makes a healthy server look dead.**

Store: `$APP_DIR`, `$LAUNCH_CMD`, `$PORT`, `$OPENS_BROWSER`

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
- If NO devices are connected: "No physical iOS device connected. Connect a device and try again, or use `/dev:launch ios sim`."

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
Stop the server: /dev:launch-kill <PORT>
```

---

### 3F — Framework Web App (Next / Vite / Astro / SvelteKit / CRA …)

Use when `HAS_WEBAPP`. The app needs **its own dev server**; serving the directory statically (3E)
would hand the browser raw source.

#### 3F.1 — Is one already running? CHECK FIRST, ALWAYS

```bash
lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null
```

**If something is listening → do NOT start anything. Open the browser and stop.**

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://localhost:$PORT"
open "http://localhost:$PORT"     # macOS · Linux: xdg-open · Windows: start
```

Report it as reuse: *"Your server was already up on :3007 — opened it, started nothing."*

This is a **guard, not an optimisation.** Launch scripts commonly free the port before binding —
this repo's does, with `lsof -ti tcp:3007 | xargs kill` on its first line. Running one against a
live server silently kills the developer's process and replaces it with yours. Their server is
theirs: you may open it, never restart it.

If the port answers but the response looks wrong (404 on `/`, a different app), say so and ask
rather than killing it.

#### 3F.2 — Nothing running → start it

Use `$LAUNCH_CMD` from Step 2.6.2 — the project's own script when it has one, the package.json
script otherwise. Run from `$APP_DIR` (or the script's own directory), backgrounded and disowned so
the terminal stays free:

```bash
cd "$APP_DIR"
$LAUNCH_CMD >/tmp/run-webapp-$PORT.log 2>&1 &
disown
```

**Say what you are about to run, before running it** — a launch script can start Docker, boot a
local database, or pull remote env, and that is not a surprise to spring on someone.

#### 3F.3 — Wait for it to actually listen

Dev servers take seconds to bind, and framework startup is not instant. Poll rather than sleeping a
guessed interval:

```bash
for i in $(seq 1 60); do
  nc -z localhost "$PORT" 2>/dev/null && break
  sleep 1
done
nc -z localhost "$PORT" 2>/dev/null || { tail -40 /tmp/run-webapp-$PORT.log; exit 1; }
```

**On timeout, print the log and STOP.** Do not open a browser at a port nothing is serving — a
blank tab is a worse error message than the stack trace sitting in the log.

#### 3F.4 — Open the browser

Skip if `$OPENS_BROWSER` — the project's script already does it, and a second tab is noise.

```bash
open "http://localhost:$PORT"
```

#### 3F.5 — Report, including how to stop it

```
Running <app-name> on http://localhost:<PORT>   (started by this skill)
Log:  /tmp/run-webapp-<PORT>.log
Stop: /dev:launch-kill
```

**Do not print `lsof -ti:<PORT> | xargs kill`.** It kills the listener and nothing else, so every
background process the launch script started — a build worker, a queue consumer — reparents to init
and keeps running. Observed 2026-08-05: three `worker.py` processes leaked this way, one per dev
session, all still polling the same local queue. `/dev:launch-kill` kills the tree from the top so
the script's own traps fire.

**Teardown rule: stop only what you started.** If 3F.1 found the server already up, you started
nothing — say that, and never offer to stop it. If the launch script also started a database or a
container, say what is now running that was not before.

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
| Webapp: port answers but it's a different app | Say so and ASK — never kill a process you did not start |
| Webapp: server never binds within 60s | Print `/tmp/run-webapp-<PORT>.log` and stop; do not open a blank tab |
| Webapp: launch script needs Docker / a local DB | Its prerequisites are the project's, not yours to bypass — surface the script's own error |
| Web: `python3` not installed | Fall back to `npx http-server "$SERVE_DIR" -p "$PORT"` or `php -S localhost:$PORT -t "$SERVE_DIR"` |
| `xcrun: error: unable to find utility "simctl"` | NOT "no Xcode". `xcode-select -p` is on Command Line Tools — set `DEVELOPER_DIR` per **2.3.0**. Every iOS step fails this way, and it reads as "no simulators" |
| `adb: command not found` | NOT "Android unavailable". Try `${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb` — it is routinely installed off `PATH` (Step 2.0, rule 1) |
| `$PROJECT_ROOT` resolves to `/` or to a parent directory | You are in a git **worktree**, where `.git` is a file. Use `git rev-parse --show-toplevel` (**2.1**). Every detector below searches the wrong tree, and `dev:launch-kill` would treat the whole machine as owned |
| `launch.json` / `tasks.json` fails to parse | They are **JSONC** — comments and trailing commas. `json.loads` cannot read them, and stripping `//` corrupts `http://`. Use the string-aware parser in **2.2a**; on failure fall through to filename guessing and SAY SO |
| `xcodebuild -list` shows few or no schemes | Report "no **shared** schemes", not "no schemes" — unshared ones live in gitignored `xcuserdata/` (**2.3.2**) |

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
- **Check the port BEFORE launching a webapp.** If it is already serving, open it and start nothing — launch scripts often free the port first, so running one against a live server kills the developer's process
- **Prefer the project's own launch script over `npm run dev`.** Test for it (`.vscode/dev.sh`, `bin/dev`, `scripts/dev*`, a Makefile target); never hardcode a path, and always fall back to the package.json script. A wrapper usually exists because the bare command produces a differently configured app
- **Stop only what you started**, and say which case it was
- For web, never open an HTML file directly with `file://` if it contains `<script src="...">`, fetch, JSX, or modules — always serve over HTTP
- For web, run the server in the background (`&` + `disown`) so the user keeps their terminal, and tell them how to stop it — **always `/dev:launch-kill`, never a bare port kill**, which orphans whatever the launch script started alongside the server
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
- The user explicitly told you to skip post-launch notes (e.g. `/dev:launch quiet`).
