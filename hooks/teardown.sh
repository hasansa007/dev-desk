#!/usr/bin/env bash
# Phase 11 HARD RULE — tear down what you started.
# Stop hook. Exit 2 blocks the stop and returns stderr to the model.
set -uo pipefail

HOOKDIR="$HOME/.claude/hooks"
log(){ printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" teardown "$1" "${2:-}" >>"$HOOKDIR/fired.log"; }

IN=$(cat)
ACTIVE=$(jq -r '.stop_hook_active // false' <<<"$IN")
# Match the LAUNCH FLAG, not the bare path: Phase 11's own teardown command
# ("ps ax | grep chrome-devtools-mcp/chrome-profile") mentions the path too, and
# counting it made the hook block on the evidence that it had already been obeyed.
# Bracket the first char so ps never counts this pipeline's own grep, and drop our
# own process tree for the same reason.
N=$(ps ax -o pid=,command= \
    | grep -E -- '--user-data-dir=[^[:space:]]*[c]hrome-devtools-mcp/chrome-profile' \
    | grep -vcE "^[[:space:]]*($$|$PPID)[[:space:]]" || true)

[ "${N:-0}" -eq 0 ]     && { log pass ""; exit 0; }
[ "$ACTIVE" = "true" ]  && { log giveup "$N"; exit 0; }   # already blocked once — never loop

log deny "$N"
cat >&2 <<'EOF'
Phase 11 — MCP debug Chrome is still running. Kill it BY ITS PROFILE, then report the line.

  ps ax -o pid,command | grep "chrome-devtools-mcp/chrome-profile" | grep -v grep
  kill <pid>; sleep 2
  ps ax -o pid,command | grep -c "[c]hrome-devtools-mcp/chrome-profile"   # expect 0

Never match on "Google Chrome" — that is the developer's own browser and their tabs.
Confirm their dev server survived: lsof -nP -iTCP:<port> -sTCP:LISTEN
Leave the MCP server alone; only the browser dies.
EOF
exit 2
