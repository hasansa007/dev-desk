#!/usr/bin/env bash
# Phase 3 — cut the branch at the FIRST WRITE.
#   PreToolUse: Edit|Write|MultiEdit|NotebookEdit  → the edit itself
#   PreToolUse: Bash                               → git commit (catches sed/python writes)
# Exit 2 = deny; stderr is fed back to the model as the reason.
set -uo pipefail

HOOKDIR="$HOME/.claude/hooks"
log(){ printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" branch-guard "$1" "${2:-}" >>"$HOOKDIR/fired.log"; }

IN=$(cat)
TOOL=$(jq -r '.tool_name // ""'            <<<"$IN")
CMD=$( jq -r '.tool_input.command // ""'   <<<"$IN")
FP=$(  jq -r '.tool_input.file_path // ""' <<<"$IN")
CWD=$( jq -r '.cwd // ""'                  <<<"$IN")

# Bash guards only the commit — an edit via sed/python is caught there instead.
if [ "$TOOL" = "Bash" ] && ! grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]+commit\b' <<<"$CMD"; then
  exit 0
fi

DIR=$CWD; [ -n "$FP" ] && DIR=$(dirname "$FP")
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/.claude/hooks-off" ] && { log bypass "$ROOT"; exit 0; }

# --show-current, not rev-parse HEAD: the latter fails on an unborn branch,
# which would let the very first write into a fresh repo's main through.
BR=$(git -C "$ROOT" branch --show-current 2>/dev/null) || exit 0
case "$BR" in
  main|master|staging) ;;
  *) log pass "$BR"; exit 0 ;;
esac

log deny "$BR"
cat >&2 <<EOF
Phase 3 — first WRITE while still on '$BR' ($(basename "$ROOT")).

  Bug:     cut it now  ->  git switch -c gh-<N>-<slug> --no-track origin/<pre-prod>
  Feature: cut it AFTER Phase 5's go-ahead, not before.

override: touch "$ROOT/.claude/hooks-off"   (logged)
EOF
exit 2
