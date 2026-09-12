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

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed. Install it with:  brew install xcodegen" >&2
    exit 1
fi

echo "==> Generating the Xcode project from project.yml"
xcodegen generate --spec project.yml >/dev/null

echo "==> Building Release (ad-hoc signed, as desk-release.yml does)"
# No -derivedDataPath: a build database inside the repo fails with a disk I/O error under some
# sandboxes, and the default location works everywhere.
xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -configuration Release \
    -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build >/tmp/dev-desk-install.log 2>&1 \
    || { echo "Build failed. Last 20 lines of /tmp/dev-desk-install.log:" >&2; tail -20 /tmp/dev-desk-install.log >&2; exit 1; }

BUILT=$(xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -configuration Release \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
SRC="$BUILT/$APP_NAME"
[ -d "$SRC" ] || { echo "Built app not found at $SRC" >&2; exit 1; }

if pgrep -x "Dev Desk" >/dev/null 2>&1; then
    echo "==> Quitting the running Dev Desk"
    osascript -e 'tell application "Dev Desk" to quit' >/dev/null 2>&1 || pkill -x "Dev Desk" || true
    sleep 1
fi

echo "==> Installing to $DEST/$APP_NAME"
mkdir -p "$DEST"
rm -rf "${DEST:?}/$APP_NAME"
ditto "$SRC" "$DEST/$APP_NAME"

# Prove what landed, rather than trusting that it did.
BIN="$DEST/$APP_NAME/Contents/MacOS/Dev Desk"
echo "    installed: $(stat -f '%Sm' "$BIN")   $(du -h "$BIN" | cut -f1)   $(codesign -dv "$DEST/$APP_NAME" 2>&1 | awk -F= '/Signature/{print $2}')"

if [ "${1:-}" = "--no-open" ]; then
    echo "==> Not launching (--no-open)"
else
    echo "==> Launching"
    open -a "$DEST/$APP_NAME"
fi
