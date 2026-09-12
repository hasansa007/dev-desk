#!/usr/bin/env bash
# Generates the Xcode project from project.yml and opens it. The project itself stays out of git
# (ADR 0012): project.yml is the source of truth, so this is the one command needed to work on the app.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed. Install it with:  brew install xcodegen" >&2
    exit 1
fi

xcodegen generate --spec project.yml
open DevDesk.xcodeproj
echo "Opened DevDesk.xcodeproj. The first build resolves SwiftTerm, so it needs the network once."
