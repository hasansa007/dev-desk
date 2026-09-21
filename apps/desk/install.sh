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
    # What counts as running is WORK, not a process (2026-09-19): a Claude session that finished its turn stays
    # alive at its prompt with its MCP helpers, and counting processes blocked installs on sessions that had been
    # idle for hours. Two things are work:
    #   1. a session mid-turn — Dev Desk writes `.working` (its own pid inside) into the session's event folder
    #      on a turn start and removes it on a finished turn, a question or an exit (AgentHooks.markWorking);
    #   1b. a session that ASKED and is waiting for the answer — `.asking`, written on a question and cleared when
    #      the next turn begins. Quitting throws the pending decision away, so it counts as work (2026-09-20);
    #   2. a headless background run — `claude -p` / `codex exec` under Dev Desk, which has no prompt to idle at;
    #   3. a session running a CLI that reports nothing — gemini, opencode, antigravity. `AgentProtocol` is the
    #      table: a CLI that never reports the end of a turn is marked working from its start until it exits, so
    #      such a session shows up above as `.working` rather than being guessed idle.
    ROOTS="$(pgrep -x 'Dev Desk' | tr '\n' ' ')"
    EVENTS="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo "${TMPDIR:-/tmp}/")devdesk-events"
    WORKING=0
    ASKING=0
    for marker in "$EVENTS"/*/.working "$EVENTS"/*/.asking; do
        [ -f "$marker" ] || continue
        owner=$(cat "$marker" 2>/dev/null)
        case " $ROOTS " in *" $owner "*) ;; *) continue ;; esac            # a crashed app's marker is ignored
        case "$marker" in *.asking) ASKING=$((ASKING + 1)) ;; *) WORKING=$((WORKING + 1)) ;; esac
    done
    SILENT=$(ps -axo pid=,ppid=,args= | awk -v roots="$ROOTS" '
        BEGIN { split(roots, r, " "); for (i in r) if (r[i] != "") seen[r[i]] = 1 }
        { pid[NR] = $1; par[NR] = $2; $1 = ""; $2 = ""; args[NR] = $0; n = NR }
        END {
            changed = 1
            while (changed) {
                changed = 0
                for (i = 1; i <= n; i++) if (!(pid[i] in seen) && (par[i] in seen)) { seen[pid[i]] = 1; changed = 1 }
            }
            for (i = 1; i <= n; i++) if ((pid[i] in seen) && args[i] ~ /(^|\/)(gemini|opencode|antigravity)( |$)/) c++
            print c + 0
        }')
    HEADLESS=$(ps -axo pid=,ppid=,args= | awk -v roots="$ROOTS" '
        BEGIN { split(roots, r, " "); for (i in r) if (r[i] != "") seen[r[i]] = 1 }
        { pid[NR] = $1; par[NR] = $2; $1 = ""; $2 = ""; args[NR] = $0; n = NR }
        END {
            changed = 1
            while (changed) {
                changed = 0
                for (i = 1; i <= n; i++) if (!(pid[i] in seen) && (par[i] in seen)) { seen[pid[i]] = 1; changed = 1 }
            }
            for (i = 1; i <= n; i++) if ((pid[i] in seen) && args[i] ~ /(^|\/)(claude|opencode)( .*)? (-p|--print)( |$)|(^|\/)codex( .*)? exec( |$)/) c++
            print c + 0
        }')
    if [ "$WORKING" -gt 0 ] || [ "$ASKING" -gt 0 ] || [ "$HEADLESS" -gt 0 ] || [ "$SILENT" -gt 0 ]; then
        echo "Dev Desk is working: $WORKING session(s) mid-turn, $ASKING waiting on a question, $HEADLESS background run(s), $SILENT session(s) whose CLI reports no turns." >&2
        echo "Installing quits the app, which would end them — a pending question is lost with it. Answer or finish them, or re-run with --force." >&2
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
# -n: LaunchServices can still count the quit app as running, and a plain `open` then starts nothing while
# exiting 0 (2026-09-21). The quit above waited for every process to exit, so -n cannot make a second one.
open -n "$DEST/$APP_NAME"
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
