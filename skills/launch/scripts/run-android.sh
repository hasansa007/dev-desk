#!/bin/bash
# run-android.sh — build an Android app and launch it on one device, in one command.
#
# Phase 3C of dev:launch, as an executable, and the counterpart to run-ios.sh. The prose version of
# that phase is four commands the caller has to keep in agreement, and on Android the ways they fall
# out of agreement are WORSE than iOS's, because more of them report success:
#
#   * `adb install` on an older adb prints `Failure [INSTALL_FAILED_...]` to stdout and exits 0.
#     `./gradlew install... && adb shell am start` therefore launches whatever was installed
#     BEFORE — the previous build, or a release build from months ago.
#   * `adb shell am start` prints `Error type 3 ... does not exist` and exits 0 as well. A wrong
#     activity name is indistinguishable from a launch, unless the output is read.
#   * `./gradlew :app:installDebug` installs to EVERY connected device. With a phone plugged in and
#     an emulator running, "it worked" and "it went somewhere else" look identical.
#   * `$ANDROID_SERIAL` silently redirects every adb command in the shell. Unlike iOS's ambiguity,
#     this one is invisible rather than merely unprompted.
#   * `applicationIdSuffix ".debug"` makes the INSTALLED package differ from the `applicationId` in
#     build.gradle and from the manifest's package. Launching the source-derived name starts the
#     release build if one is installed, and fails silently (see above) if not.
#   * `adb wait-for-device` returns when adbd answers, which is minutes before the system has
#     booted. Installing there fails with a message that reads like a broken APK.
#   * The APK path is `app/build/outputs/apk/debug/app-debug.apk` only WITHOUT product flavors.
#     With them it is `.../apk/<flavor>/debug/app-<flavor>-debug.apk`, and the hardcoded path finds
#     either nothing or something stale.
#
# So this resolves ONE device serial, passes `-s` to every adb call, reads the package and activity
# out of the BUILT APK rather than out of source, and treats adb's stdout as the exit status adb
# does not give.
#
#   run-android.sh                          # the running device/emulator, else boot the first AVD
#   run-android.sh emulator-5554            # exactly that serial
#   run-android.sh --avd Pixel_7_API_34     # boot this AVD if nothing is running
#   run-android.sh --module :app            # when more than one module applies the app plugin
#   run-android.sh --package com.example    # when no aapt2 and the APK's package cannot be read
#   run-android.sh --root path/to/repo      # project root, if not the current git worktree
#   run-android.sh --shot                   # also write and open a screenshot after launching
#   run-android.sh --release                # Release configuration instead of Debug
#
# Nothing is hardcoded — module, APK, package and activity are all detected. Dependencies are bash,
# adb, the project's gradlew, and (for reading the APK) aapt2 from the SDK's build-tools; when
# aapt2 is absent the device itself is asked instead, so the script still works, one step later.
#
# Exit 0 = app launched. Exit 1 = build, install or launch failed. Exit 2 = could not resolve the
# SDK, the project, the module, or a device.

set -uo pipefail

CONFIGURATION="Debug"
WANT_SHOT=false
SERIAL_ARG=""
MODULE_ARG=""
AVD_ARG=""
PACKAGE_ARG=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shot)     WANT_SHOT=true ;;
    --release)  CONFIGURATION="Release" ;;
    --debug)    CONFIGURATION="Debug" ;;
    --module)   shift; MODULE_ARG="${1:-}" ;;
    --package)  shift; PACKAGE_ARG="${1:-}" ;;
    --avd)      shift; AVD_ARG="${1:-}" ;;
    --root)     shift; PROJECT_ROOT="${1:-}" ;;
    -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*)         echo "run-android.sh: unknown flag $1" >&2; exit 2 ;;
    *)          SERIAL_ARG="$1" ;;
  esac
  shift
done

# An inherited ANDROID_SERIAL outranks every -s flag below in some adb versions and is invisible in
# the command line being run. Drop it: this script names its target explicitly.
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  echo "note: ignoring inherited ANDROID_SERIAL=$ANDROID_SERIAL — this run targets one resolved serial."
  unset ANDROID_SERIAL
fi

# --- Project root ------------------------------------------------------------------------------
# git first: it is the only form that gets WORKTREES right. In a worktree `.git` is a FILE, so a
# `-d .git` walk never terminates and resolves the root to `/`.
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$PWD"
  while [[ "$PROJECT_ROOT" != "/" ]]; do
    [[ -f "$PROJECT_ROOT/gradlew" ]] && break
    [[ -e "$PROJECT_ROOT/.git" ]] && break
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
  done
fi
cd "$PROJECT_ROOT" 2>/dev/null || { echo "run-android.sh: cannot enter $PROJECT_ROOT" >&2; exit 2; }

if [[ ! -f "$PROJECT_ROOT/gradlew" ]]; then
  echo "run-android.sh: no gradlew at $PROJECT_ROOT — not a Gradle project root." >&2
  echo "  Pass --root PATH if the Android project lives elsewhere." >&2
  exit 2
fi
[[ -x "$PROJECT_ROOT/gradlew" ]] || chmod +x "$PROJECT_ROOT/gradlew"

# --- SDK and adb -------------------------------------------------------------------------------
# Step 2.0 rule 1: installed is not the same as reachable. adb ships inside the SDK and is on PATH
# only if the developer put it there, so a bare `command -v adb` reports "no Android" on a machine
# with a working SDK. Rule 2: if none of these hold it, say which ones were tried.
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB=""
for candidate in "$(command -v adb 2>/dev/null)" \
                 "$SDK_ROOT/platform-tools/adb" \
                 "$HOME/Library/Android/sdk/platform-tools/adb" \
                 "$HOME/Android/Sdk/platform-tools/adb"; do
  [[ -n "$candidate" && -x "$candidate" ]] && { ADB="$candidate"; break; }
done
if [[ -z "$ADB" ]]; then
  echo "run-android.sh: no usable adb." >&2
  echo "  PATH:            $(command -v adb 2>/dev/null || echo 'not on PATH')" >&2
  echo "  ANDROID_HOME:    ${ANDROID_HOME:-unset}" >&2
  echo "  searched:        \$ANDROID_HOME/platform-tools/adb, ~/Library/Android/sdk/platform-tools/adb, ~/Android/Sdk/platform-tools/adb" >&2
  exit 2
fi
[[ -d "$SDK_ROOT" ]] || SDK_ROOT="$(cd "$(dirname "$ADB")/.." && pwd)"

# aapt2 reads the built APK. Newest build-tools wins; -V keeps 9.0.0 from outranking 35.0.0.
AAPT=""
while IFS= read -r dir; do
  [[ -x "$dir/aapt2" ]] && { AAPT="$dir/aapt2"; break; }
  [[ -x "$dir/aapt" ]]  && { AAPT="$dir/aapt";  break; }
done < <(ls -1d "$SDK_ROOT"/build-tools/*/ 2>/dev/null | sed 's:/$::' | sort -Vr 2>/dev/null || ls -1d "$SDK_ROOT"/build-tools/*/ 2>/dev/null | sed 's:/$::' | sort -r)

# --- App module --------------------------------------------------------------------------------
# The module that applies com.android.application — NOT ":app" by name. A KMP project calls it
# :androidApp, and a project can carry several application modules (a demo, a wear app).
#
# Grepping the module for the literal plugin id finds NOTHING on a version-catalog project, because
# the id lives in gradle/libs.versions.toml and the module says `alias(libs.plugins.…)`. So resolve
# the alias through the catalog first, and match either form. Lines carrying `apply false` are
# excluded: the ROOT build file declares every plugin that way without applying any of them, and it
# would otherwise be picked as the app module.
CATALOG="$PROJECT_ROOT/gradle/libs.versions.toml"
APP_PLUGIN_RE='com\.android\.application'
if [[ -f "$CATALOG" ]]; then
  while IFS= read -r alias_key; do
    [[ -z "$alias_key" ]] && continue
    accessor="$(printf '%s' "$alias_key" | tr '_-' '..' | sed 's/\./\\./g')"
    APP_PLUGIN_RE="$APP_PLUGIN_RE|libs\\.plugins\\.$accessor"
  done < <(sed -n '/^\[plugins\]/,/^\[/p' "$CATALOG" \
           | grep -E 'id[[:space:]]*=[[:space:]]*"com\.android\.application"' \
           | sed -E 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=.*/\1/')
fi

applies_app_plugin() {   # 0 if $1 applies the Android application plugin
  local hits
  hits="$(grep -E "$APP_PLUGIN_RE" "$1" 2>/dev/null | grep -v 'apply false' | grep -c . || true)"
  [[ "$hits" -gt 0 ]]
}

if [[ -n "$MODULE_ARG" ]]; then
  APP_MODULE_PATH="${MODULE_ARG#:}"
  APP_MODULE_PATH="${APP_MODULE_PATH//://}"
  if [[ ! -d "$PROJECT_ROOT/$APP_MODULE_PATH" ]]; then
    echo "run-android.sh: --module $MODULE_ARG is not a directory under $PROJECT_ROOT." >&2
    exit 2
  fi
else
  MODULE_COUNT=0
  ALL_MODULES=""
  APP_MODULE_PATH=""
  while IFS= read -r gradlefile; do
    applies_app_plugin "$gradlefile" || continue
    dir="$(dirname "$gradlefile")"
    rel="${dir#"$PROJECT_ROOT"/}"
    [[ "$rel" == "$PROJECT_ROOT" ]] && continue      # the root build file is not a module
    MODULE_COUNT=$((MODULE_COUNT + 1))
    [[ -z "$APP_MODULE_PATH" ]] && APP_MODULE_PATH="$rel"
    ALL_MODULES="${ALL_MODULES:+$ALL_MODULES, }:${rel//\//:}"
  done < <(find "$PROJECT_ROOT" -maxdepth 3 \( -name build.gradle -o -name build.gradle.kts \) -not -path "*/build/*" -not -path "*/.*" 2>/dev/null | sort)

  if [[ "$MODULE_COUNT" -eq 0 ]]; then
    echo "run-android.sh: no module applies the Android application plugin under $PROJECT_ROOT." >&2
    echo "  searched: build.gradle / build.gradle.kts to depth 3, excluding build/ and dotdirs" >&2
    echo "  matched:  $APP_PLUGIN_RE" >&2
    echo "  catalog:  ${CATALOG}$([[ -f "$CATALOG" ]] || echo ' (absent — alias form not resolvable)')" >&2
    exit 2
  elif [[ "$MODULE_COUNT" -gt 1 ]]; then
    # Refusing to guess, exactly as run-ios.sh does for schemes: picking the first of several
    # application modules is how you build the demo app and wonder why the fix is not in it.
    echo "run-android.sh: more than one Android application module — pass --module :name." >&2
    echo "  candidates: $ALL_MODULES" >&2
    exit 2
  fi
fi
APP_MODULE=":${APP_MODULE_PATH//\//:}"

# --- Device ------------------------------------------------------------------------------------
# A running device outranks booting a new emulator. `adb devices` also lists offline/unauthorized
# entries, which are not usable targets and must not be picked silently.
pick_device() {
  "$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }'
}

SERIAL=""
if [[ -n "$SERIAL_ARG" ]]; then
  if pick_device | grep -qx "$SERIAL_ARG"; then
    SERIAL="$SERIAL_ARG"
  else
    echo "run-android.sh: $SERIAL_ARG is not an available device." >&2
    echo "  adb devices reports:" >&2
    "$ADB" devices | sed 's/^/    /' >&2
    exit 2
  fi
else
  READY="$(pick_device)"
  READY_COUNT="$(printf '%s' "$READY" | grep -c . || true)"
  if [[ "$READY_COUNT" -gt 1 ]]; then
    # adb itself errors on ambiguity rather than picking, which is kinder than simctl — but the
    # error arrives four commands later. Ask here, where the question still makes sense.
    echo "run-android.sh: more than one device — name one." >&2
    printf '  candidates: %s\n' "$(printf '%s' "$READY" | tr '\n' ' ')" >&2
    exit 2
  elif [[ "$READY_COUNT" -eq 1 ]]; then
    SERIAL="$READY"
  fi
fi

if [[ -z "$SERIAL" ]]; then
  EMULATOR_BIN="$SDK_ROOT/emulator/emulator"
  if [[ ! -x "$EMULATOR_BIN" ]]; then
    echo "run-android.sh: no device connected and no emulator binary at $EMULATOR_BIN." >&2
    exit 2
  fi
  AVD="$AVD_ARG"
  [[ -z "$AVD" ]] && AVD="$("$EMULATOR_BIN" -list-avds 2>/dev/null | head -1)"
  if [[ -z "$AVD" ]]; then
    echo "run-android.sh: no device connected and no AVD configured." >&2
    echo "  Create one in Android Studio (Tools > Device Manager), or connect a device." >&2
    exit 2
  fi
  echo "Booting emulator: $AVD"
  nohup "$EMULATOR_BIN" -avd "$AVD" >/dev/null 2>&1 &

  # wait-for-device returns when adbd answers — minutes before the system is usable. The property
  # is the only thing that means "booted"; installing before it is set fails in a way that reads
  # like a broken APK.
  "$ADB" wait-for-device
  SERIAL="$(pick_device | head -1)"
  [[ -z "$SERIAL" ]] && { echo "run-android.sh: emulator started but no device appeared." >&2; exit 2; }
  printf 'Waiting for boot to complete'
  for _ in $(seq 1 180); do
    [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
    printf '.'
    sleep 1
  done
  echo
  if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
    echo "run-android.sh: $SERIAL did not finish booting within 180s." >&2
    exit 2
  fi
fi

DEVICE_MODEL="$("$ADB" -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
DEVICE_SDK="$("$ADB" -s "$SERIAL" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
case "$SERIAL" in emulator-*) DEVICE_KIND="Emulator" ;; *) DEVICE_KIND="Device" ;; esac

# Phase 3's "before executing" summary. Package and activity are deliberately absent: they are read
# from the APK further down, and printing a guess here that the build then contradicts is the whole
# failure this script exists to remove.
echo "## Run: $(basename "$PROJECT_ROOT")"
echo "Platform:  Android"
echo "Target:    $DEVICE_KIND (${DEVICE_MODEL:-unknown}, API ${DEVICE_SDK:-?}, $SERIAL)"
echo "Config:    $CONFIGURATION"
echo "Module:    $APP_MODULE"
echo "Project:   $PROJECT_ROOT"
echo

# --- Build -------------------------------------------------------------------------------------
# assemble, NOT install: `:module:installDebug` installs to EVERY connected device, and this script
# exists to target exactly one. Not piped into tail/grep either — a pipeline takes the LAST
# command's status, so a failed build would report success and the install below would push a stale
# APK from a previous run.
"$PROJECT_ROOT/gradlew" "$APP_MODULE:assemble$CONFIGURATION" --console=plain || exit 1

# --- APK ---------------------------------------------------------------------------------------
# Newest by mtime under the module's own outputs. The conventional path holds only for a project
# without product flavors; with them the flavor is a directory level that is not known here.
LOWER_CONFIG="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
APK="$(
  find "$PROJECT_ROOT/$APP_MODULE_PATH/build/outputs/apk" -name '*.apk' -type f 2>/dev/null |
  grep -i "/$LOWER_CONFIG/" |
  while IFS= read -r path; do printf '%s\t%s\n' "$(stat -f '%m' "$path")" "$path"; done |
  sort -rn | head -1 | cut -f2-
)"
if [[ -z "$APK" ]]; then
  echo "run-android.sh: build succeeded but no $CONFIGURATION .apk under $APP_MODULE_PATH/build/outputs/apk." >&2
  exit 1
fi

# --- Package and activity, from the ARTEFACT --------------------------------------------------
# Not from build.gradle and not from the manifest: `applicationIdSuffix ".debug"` makes the
# installed package differ from both, and a manifest with several LAUNCHER activities (flavors, a
# debug entry point) gives no way to tell which one this build actually shipped.
PACKAGE="$PACKAGE_ARG"
ACTIVITY=""
if [[ -z "$PACKAGE" && -n "$AAPT" ]]; then
  BADGING="$("$AAPT" dump badging "$APK" 2>/dev/null)"
  PACKAGE="$(printf '%s' "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
  ACTIVITY="$(printf '%s' "$BADGING" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)"
fi

# --- Install -----------------------------------------------------------------------------------
# With no aapt2 the package is still unknown here, so snapshot the installed set FIRST: whatever is
# new afterwards is what this install added. That is a measurement; reading the last line of
# `pm list packages` would be a guess, and guessing is what this script exists to stop.
PKGS_BEFORE=""
[[ -z "$PACKAGE" ]] && PKGS_BEFORE="$("$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null | tr -d '\r' | sort)"

# adb install exits 0 while printing Failure on older adb, so stdout IS the exit status here.
INSTALL_OUT="$("$ADB" -s "$SERIAL" install -r -t "$APK" 2>&1)"
INSTALL_RC=$?
if [[ "$INSTALL_RC" -ne 0 ]] || printf '%s' "$INSTALL_OUT" | grep -q 'Failure'; then
  echo "$INSTALL_OUT" >&2
  if printf '%s' "$INSTALL_OUT" | grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE\|signatures do not match'; then
    # Uninstalling wipes the app's data. That is the developer's call, not this script's.
    echo "run-android.sh: an existing install was signed with a different key." >&2
    echo "  Fix by removing it FIRST — this deletes its data: $ADB -s $SERIAL uninstall ${PACKAGE:-<package>}" >&2
  fi
  exit 1
fi

# aapt2 absent: the package is whatever appeared on the device that was not there a moment ago.
if [[ -z "$PACKAGE" ]]; then
  NEW_PKGS="$(comm -13 <(printf '%s\n' "$PKGS_BEFORE") \
                       <("$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null | tr -d '\r' | sort) \
              | sed 's/^package://')"
  NEW_COUNT="$(printf '%s' "$NEW_PKGS" | grep -c . || true)"
  if [[ "$NEW_COUNT" -eq 1 ]]; then
    PACKAGE="$NEW_PKGS"
    echo "note: aapt2 not found under $SDK_ROOT/build-tools — package resolved from the device."
  else
    # 0 means it was already installed under a name this run cannot see; >1 means something else
    # installed concurrently. Both are cases where picking one would be a coin toss.
    echo "run-android.sh: installed, but could not determine which package to launch." >&2
    echo "  aapt2 is absent (searched $SDK_ROOT/build-tools) and the install added $NEW_COUNT new packages." >&2
    echo "  Pass --package NAME, or install Android SDK build-tools so the APK can be read directly." >&2
    exit 1
  fi
fi
if [[ -z "$ACTIVITY" ]]; then
  ACTIVITY="$("$ADB" -s "$SERIAL" shell cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tr -d '\r' | tail -1)"
  ACTIVITY="${ACTIVITY#*/}"
fi
if [[ -z "$ACTIVITY" ]]; then
  echo "run-android.sh: installed $PACKAGE, but no launchable activity was found." >&2
  exit 1
fi
case "$ACTIVITY" in "$PACKAGE"/*) COMPONENT="$ACTIVITY" ;; *) COMPONENT="$PACKAGE/$ACTIVITY" ;; esac

echo "Package:   $PACKAGE"
echo "Activity:  $COMPONENT"

# --- Launch ------------------------------------------------------------------------------------
# `am start` prints "Error type 3" and exits 0 when the component does not exist, so again the
# output is the status. Stop first, so a running instance is genuinely relaunched.
"$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null 2>&1
LAUNCH_OUT="$("$ADB" -s "$SERIAL" shell am start -n "$COMPONENT" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>&1 | tr -d '\r')"
if printf '%s' "$LAUNCH_OUT" | grep -qi 'error'; then
  echo "$LAUNCH_OUT" >&2
  exit 1
fi

if [[ "$WANT_SHOT" == true ]]; then
  SHOT="${TMPDIR:-/tmp}/$(basename "$APP_MODULE_PATH")-$(date +%Y%m%d-%H%M%S).png"
  if "$ADB" -s "$SERIAL" exec-out screencap -p > "$SHOT" 2>/dev/null && [[ -s "$SHOT" ]]; then
    echo "Screenshot: $SHOT"
    open "$SHOT" 2>/dev/null || true
  fi
fi

echo "App launched successfully on ${DEVICE_MODEL:-$SERIAL}."
