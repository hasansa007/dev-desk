#!/bin/bash
# run-ios.sh — build an iOS app and launch it on a simulator, in one command.
#
# Phase 3A of dev:launch, as an executable. The prose version of that phase is four commands the
# caller has to keep in agreement — and the ways they fall out of agreement do not error, they
# succeed against the wrong thing:
#
#   * `-destination 'name=iPhone 17 Pro'` and `simctl ... booted` are both AMBIGUOUS the moment two
#     runtimes carry a device of the same name, which is the normal state of a machine with two iOS
#     SDKs installed. Neither errors. Each picks. Build for one device, read the screen of another,
#     and the app looks like it ignored the change.
#   * Piping `xcodebuild` into `tail`/`grep` before `&&` hands the pipeline the LAST command's exit
#     status, so a failed build reports success and the install pushes the previous `.app`.
#   * DerivedData accumulates a directory per project path, so a stale sibling from an old worktree
#     is indistinguishable from what was just built unless you sort by mtime.
#
# This resolves ONE device UDID and hands the same one to every step.
#
#   run-ios.sh                            # newest booted iPhone, else the newest available one
#   run-ios.sh "iPhone 17 Pro Max"        # a device by name — newest runtime wins if it repeats
#   run-ios.sh <UDID>                     # exactly that device
#   run-ios.sh --scheme App               # when the project has more than one app scheme
#   run-ios.sh --root path/to/repo        # project root, if not the current git worktree
#   run-ios.sh --shot                     # also write and open a screenshot after launching
#   run-ios.sh --release                  # Release configuration instead of Debug
#
# Nothing is hardcoded — scheme, product path, bundle ID and device are all detected. Dependencies
# are bash, xcrun, and the python3 that ships with macOS; python3 reads `simctl list -j` rather
# than grepping the text listing, because picking the newest runtime out of that listing by eye is
# the ambiguity this exists to remove.
#
# Builds into the shared DerivedData deliberately: a run here and a run from Xcode.app then reuse
# each other's incremental build instead of each keeping a copy.
#
# Exit 0 = app launched. Exit 1 = build, install or launch failed. Exit 2 = could not resolve the
# toolchain, the project, the scheme, or a device.

set -uo pipefail

CONFIGURATION="Debug"
WANT_SHOT=false
DEVICE_ARG=""
SCHEME_ARG=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shot)     WANT_SHOT=true ;;
    --release)  CONFIGURATION="Release" ;;
    --debug)    CONFIGURATION="Debug" ;;
    --scheme)   shift; SCHEME_ARG="${1:-}" ;;
    --root)     shift; PROJECT_ROOT="${1:-}" ;;
    -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*)         echo "run-ios.sh: unknown flag $1" >&2; exit 2 ;;
    *)          DEVICE_ARG="$1" ;;
  esac
  shift
done

# --- Project root ------------------------------------------------------------------------------
# git first: it is the only form that gets WORKTREES right. In a worktree `.git` is a FILE, so a
# `-d .git` walk never terminates and resolves the root to `/`.
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$PWD"
  while [[ "$PROJECT_ROOT" != "/" ]]; do
    if ls "$PROJECT_ROOT"/*.xcworkspace "$PROJECT_ROOT"/*.xcodeproj >/dev/null 2>&1; then break; fi
    [[ -e "$PROJECT_ROOT/.git" ]] && break
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
  done
fi
cd "$PROJECT_ROOT" 2>/dev/null || { echo "run-ios.sh: cannot enter $PROJECT_ROOT" >&2; exit 2; }

# --- Toolchain ---------------------------------------------------------------------------------
# `xcode-select -p` on Command Line Tools ships no simctl, and every step then dies with "unable to
# find utility simctl" — a false negative on a machine that has Xcode. DEVELOPER_DIR fixes this run
# without sudo and without changing global state the developer did not ask to have changed.
if ! xcrun simctl help >/dev/null 2>&1; then
  for candidate in /Applications/Xcode*.app; do
    if [[ -x "$candidate/Contents/Developer/usr/bin/simctl" ]]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      break
    fi
  done
fi
if ! xcrun simctl help >/dev/null 2>&1; then
  echo "run-ios.sh: no usable Xcode toolchain." >&2
  echo "  xcode-select -p: $(xcode-select -p 2>/dev/null)" >&2
  echo "  searched:        /Applications/Xcode*.app/Contents/Developer/usr/bin/simctl" >&2
  exit 2
fi
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"

# --- Xcode project -----------------------------------------------------------------------------
# .xcworkspace wins over .xcodeproj where both exist — CocoaPods requires it.
XCODE_FILE=""
XCODE_FLAG=""
for subdir in "$PROJECT_ROOT" "$PROJECT_ROOT"/iOSApp "$PROJECT_ROOT"/ios "$PROJECT_ROOT"/iosApp "$PROJECT_ROOT"/App; do
  [[ -d "$subdir" ]] || continue
  candidate="$(ls -d "$subdir"/*.xcworkspace 2>/dev/null | head -1)"
  if [[ -n "$candidate" ]]; then XCODE_FILE="$candidate"; XCODE_FLAG="-workspace"; break; fi
  candidate="$(ls -d "$subdir"/*.xcodeproj 2>/dev/null | head -1)"
  if [[ -n "$candidate" ]]; then XCODE_FILE="$candidate"; XCODE_FLAG="-project"; break; fi
done
if [[ -z "$XCODE_FILE" ]]; then
  echo "run-ios.sh: no .xcworkspace or .xcodeproj under $PROJECT_ROOT (searched root, iOSApp/, ios/, iosApp/, App/)." >&2
  exit 2
fi

# --- Scheme ------------------------------------------------------------------------------------
if [[ -n "$SCHEME_ARG" ]]; then
  SCHEME="$SCHEME_ARG"
else
  SCHEME=""
  ALL_SCHEMES=""
  SCHEME_COUNT=0
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    SCHEME_COUNT=$((SCHEME_COUNT + 1))
    [[ -z "$SCHEME" ]] && SCHEME="$candidate"
    ALL_SCHEMES="${ALL_SCHEMES:+$ALL_SCHEMES, }$candidate"
  done < <(xcodebuild -list -json $XCODE_FLAG "$XCODE_FILE" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
container = d.get("project") or d.get("workspace") or {}
for s in container.get("schemes", []):
    if s.endswith(("Tests", "UITests")):
        continue
    if any(k in s for k in ("Widget", "Screenshot", "Watch", "Extension", "Clip")):
        continue
    print(s)
')

  if [[ "$SCHEME_COUNT" -eq 0 ]]; then
    # "no SHARED schemes", never "no schemes": unshared ones live in gitignored xcuserdata/, so a
    # fresh clone legitimately lists none while the project has plenty. Different facts.
    echo "run-ios.sh: no shared app scheme in $XCODE_FILE." >&2
    echo "  Unshared schemes live in gitignored xcuserdata/ and are invisible here. Pass --scheme NAME." >&2
    exit 2
  elif [[ "$SCHEME_COUNT" -gt 1 ]]; then
    echo "run-ios.sh: more than one app scheme — pass --scheme NAME." >&2
    echo "  candidates: $ALL_SCHEMES" >&2
    exit 2
  fi
fi

# --- Device ------------------------------------------------------------------------------------
# A booted device outranks a newer shutdown one: booting a third simulator to run on it is slower
# and leaves the developer with three.
PICK_DEVICE=$(cat <<'PY'
import json, re, sys

want = sys.argv[1] if len(sys.argv) > 1 else ""
data = json.load(sys.stdin)

def runtime_version(identifier):
    m = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable", True):
            continue
        candidates.append({
            "udid": d["udid"],
            "name": d["name"],
            "booted": d.get("state") == "Booted",
            "version": runtime_version(runtime),
        })

if not candidates:
    sys.stderr.write("run-ios.sh: no available iOS simulators.\n")
    sys.exit(1)

if want:
    matches = [c for c in candidates if c["udid"] == want] or \
              [c for c in candidates if c["name"] == want]
    if not matches:
        sys.stderr.write("run-ios.sh: no available simulator named or identified by %r.\n" % want)
        sys.exit(1)
    pick = max(matches, key=lambda c: c["version"])
else:
    phones = [c for c in candidates if c["name"].startswith("iPhone")] or candidates
    def rank(c):
        tier = 2 if "Pro Max" in c["name"] else 1 if "Pro" in c["name"] else 0
        return (c["booted"], c["version"], tier)
    pick = max(phones, key=rank)

print("\t".join([
    pick["udid"],
    pick["name"],
    "iOS %d.%d" % pick["version"],
    "booted" if pick["booted"] else "shutdown",
]))
PY
)

DEVICE="$(xcrun simctl list devices available -j | python3 -c "$PICK_DEVICE" "$DEVICE_ARG")" || exit 2
UDID="$(printf '%s' "$DEVICE" | cut -f1)"
SIM_LABEL="$(printf '%s' "$DEVICE" | cut -f2,3 | tr '\t' ' ')"
SIM_STATE="$(printf '%s' "$DEVICE" | cut -f4)"

# Phase 3's "before executing" summary.
echo "## Run: $(basename "$PROJECT_ROOT")"
echo "Platform:  iOS"
echo "Target:    Simulator ($SIM_LABEL, $SIM_STATE)"
echo "Config:    $CONFIGURATION"
echo "Scheme:    $SCHEME"
echo "Project:   $XCODE_FILE"
echo

if [[ "$SIM_STATE" != "booted" ]]; then
  xcrun simctl boot "$UDID" || exit 2
fi

# The GUI is a separate component from the runtime, and an Xcode install can be missing it while
# simctl drives the device perfectly well. Headless is a working state, not a failure — say it once
# and carry on, rather than reporting a launch that did work as a launch that did not.
SIMULATOR_APP="$DEVELOPER_ROOT/Applications/Simulator.app"
if [[ -d "$SIMULATOR_APP" ]]; then
  open "$SIMULATOR_APP"
else
  echo "note: no Simulator.app in this Xcode install — the device runs headless. Use --shot to see it."
fi

# --- Build -------------------------------------------------------------------------------------
# Not piped into tail/grep on purpose: a pipeline takes the LAST command's exit status, so a failed
# build would report success and the install below would push the previous .app.
xcodebuild build \
  $XCODE_FLAG "$XCODE_FILE" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration "$CONFIGURATION" \
  -quiet || exit 1

# --- Product -----------------------------------------------------------------------------------
# Newest by mtime: DerivedData keeps a directory per project path, and a stale sibling from an old
# worktree is otherwise indistinguishable from the one just built.
APP="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -maxdepth 6 -type d \
    -path "*/Build/Products/$CONFIGURATION-iphonesimulator/$SCHEME.app" 2>/dev/null |
  while IFS= read -r path; do printf '%s\t%s\n' "$(stat -f '%m' "$path")" "$path"; done |
  sort -rn | head -1 | cut -f2-
)"
if [[ -z "$APP" ]]; then
  echo "run-ios.sh: build succeeded but no $SCHEME.app found under DerivedData." >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "run-ios.sh: could not read CFBundleIdentifier from $APP/Info.plist." >&2
  exit 1
fi

# --- Install and launch --------------------------------------------------------------------------
xcrun simctl install "$UDID" "$APP" || exit 1
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1
xcrun simctl launch "$UDID" "$BUNDLE_ID" || exit 1

if [[ "$WANT_SHOT" == true ]]; then
  SHOT="${TMPDIR:-/tmp}/$SCHEME-$(date +%Y%m%d-%H%M%S).png"
  if xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1; then
    echo "Screenshot: $SHOT"
    open "$SHOT"
  fi
fi

echo "App launched successfully on $SIM_LABEL."
