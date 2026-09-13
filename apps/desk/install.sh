#!/usr/bin/env bash
# Builds Dev Desk and installs it where you actually open it: ~/Applications.
#
# `open.sh` opens the project in Xcode; running from Xcode puts the app in DerivedData, which is a
# DIFFERENT bundle from the one in ~/Applications. On 2026-09-12 that cost a whole session: every
# change was built, launched and verified in DerivedData while the developer kept opening the
# installed copy and correctly reported seeing nothing change. This script is the missing half.
#
# The build matches .github/workflows/desk-release.yml: Release, ad-hoc signed.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Dev Desk.app"
DEST="$HOME/Applications"
OPEN_AFTER=1
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_AFTER=0 ;;
        --force) FORCE=1 ;;
        *) echo "usage: install.sh [--no-open] [--force]" >&2; exit 2 ;;
    esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed. Install it with:  brew install xcodegen" >&2
    exit 1
fi

# mktemp, not a fixed /tmp path: a predictable name in a world-writable directory can be pre-created
# as a symlink and this redirect would truncate whatever it points at.
LOG=$(mktemp -t dev-desk-install)
# Deliberately NOT removed on failure: two messages below tell the reader to open it.

if pgrep -x "Dev Desk" >/dev/null 2>&1 && [ "$FORCE" -eq 0 ]; then
    # Every descendant, not two levels: a run whose agent sits under a wrapper or a re-exec was invisible to
    # a fixed-depth scan, and the guard would pass and then kill it.
    LIVE=$(ps -axo pid=,ppid=,comm= | awk -v roots="$(pgrep -x 'Dev Desk' | tr '\n' ' ')" '
        BEGIN { split(roots, r, " "); for (i in r) if (r[i] != "") seen[r[i]] = 1 }
        { pid[NR] = $1; par[NR] = $2; cmd[NR] = $3; n = NR }
        END {
            changed = 1
            while (changed) {
                changed = 0
                for (i = 1; i <= n; i++) if (!(pid[i] in seen) && (par[i] in seen)) { seen[pid[i]] = 1; changed = 1 }
            }
            for (i = 1; i <= n; i++) if (pid[i] in seen) {
                name = cmd[i]; sub(/.*\//, "", name)
                if (name == "claude" || name == "codex") print name
            }
        }' | sort -u | tr '\n' ' ')
    if [ -n "$LIVE" ]; then
        echo "Dev Desk is running something: $LIVE" >&2
        echo "Installing quits the app, which would end it. Stop it in the Runs panel, or re-run with --force." >&2
        exit 1
    fi
fi

echo "==> Generating the Xcode project from project.yml"
xcodegen generate --spec project.yml >/dev/null

echo "==> Building Release (ad-hoc signed, as desk-release.yml does)"
# No -derivedDataPath: a build database inside the repo fails with a disk I/O error under some
# sandboxes, and the default location works everywhere.
xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -configuration Release \
    -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build >"$LOG" 2>&1 \
    || { echo "Build failed. Last 20 lines of $LOG:" >&2; tail -20 "$LOG" >&2; exit 1; }

# Keep the failure visible: under `set -e` a failed substitution exits here, and discarding stderr
# would make that exit silent and the friendly message below unreachable.
BUILT=$(xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -configuration Release \
    -destination 'platform=macOS' -showBuildSettings 2>>"$LOG" \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}') || BUILT=""
[ -n "$BUILT" ] || { echo "Could not read BUILT_PRODUCTS_DIR; see $LOG" >&2; exit 1; }
SRC="$BUILT/$APP_NAME"
[ -d "$SRC" ] || { echo "Built app not found at $SRC" >&2; exit 1; }

# Quit and WAIT. `open -a` on a live process only activates it, so a survivor here means installing a
# new bundle and then bringing the OLD build to the front — the very failure this script exists to
# prevent, wearing a fresh "installed" timestamp.
wait_for_exit() {
    local deadline=$1
    while [ "$deadline" -gt 0 ]; do
        pgrep -x "Dev Desk" >/dev/null 2>&1 || return 0
        sleep 0.5
        deadline=$((deadline - 1))
    done
    return 1
}

# Installing quits the app, and quitting ends every run it is hosting. Twice on 2026-09-12 that took a
# live door run with it, both times because a human eye judged "probably finished". The check is cheap and
# the loss is not, so it is the script's job, and --force is the way to say you meant it.
# Refusal observed working 2026-09-12, against a real live run.
if pgrep -x "Dev Desk" >/dev/null 2>&1; then
    echo "==> Quitting the running Dev Desk"
    osascript -e 'tell application "Dev Desk" to quit' >/dev/null 2>&1 || true
    wait_for_exit 20 || { pkill -x "Dev Desk" || true; wait_for_exit 10; } || { pkill -9 -x "Dev Desk" || true; wait_for_exit 6; } || {
        echo "Dev Desk is still running; refusing to replace the bundle underneath it." >&2
        exit 1
    }
fi

rm -f "$LOG"

echo "==> Installing to $DEST/$APP_NAME"
mkdir -p "$DEST"
STAGE="$DEST/.$APP_NAME.new"
rm -rf "$STAGE"
# Copy first. The installed app is removed only once its replacement is on disk, so a failed copy
# leaves the old app in place rather than nothing at all.
ditto "$SRC" "$STAGE"
rm -rf "${DEST:?}/$APP_NAME"
mv "$STAGE" "$DEST/$APP_NAME"

BIN="$DEST/$APP_NAME/Contents/MacOS/Dev Desk"
echo "    installed: $(stat -f '%Sm' "$BIN")   $(du -h "$BIN" | cut -f1)   $(codesign -dv "$DEST/$APP_NAME" 2>&1 | awk -F= '/Signature/{print $2}')"

if [ "$OPEN_AFTER" -eq 0 ]; then
    echo "==> Not launching (--no-open)"
    exit 0
fi

echo "==> Launching"
open -a "$DEST/$APP_NAME"
sleep 2
# Say which bundle is actually running, rather than assuming `open` did what was asked.
# By pid, not by scanning every command line: this script's own invocation contains the app's path, so a
# grep over `ps -eo command` matches itself and reports "a different bundle is running".
RUNNING=$(pgrep -x "Dev Desk" | head -1 | xargs -I{} ps -p {} -o comm= 2>/dev/null || true)
case "$RUNNING" in
    "$DEST/$APP_NAME"*) echo "    running: $DEST/$APP_NAME" ;;
    "")                 echo "    warning: Dev Desk does not appear to be running" >&2 ;;
    *)                  echo "    warning: a different bundle is running: $RUNNING" >&2 ;;
esac
