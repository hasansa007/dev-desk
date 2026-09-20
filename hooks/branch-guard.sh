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
if [ "$TOOL" = "Bash" ] && ! grep -qE '(^|[;&|])[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit\b' <<<"$CMD"; then
  exit 0
fi

DIR=$CWD; [ -n "$FP" ] && DIR=$(dirname "$FP")
# A Bash commit runs where the COMMAND points, not where the session started: `git -C <dir> …`
# or `cd <dir> && …`. Judging the session cwd denied commits in other repos and in worktrees
# whenever the session's own folder sat on staging (2026-09-19).
if [ "$TOOL" = "Bash" ]; then
  # Candidates in order — every `git -C` target, then a `cd` on the command's FIRST line — and the
  # first that is a real directory wins. A commit message quoting "git -C <dir>" must not win.
  CANDS=$( { grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:];&|]+' <<<"$CMD" | awk '{print $3}'
             head -1 <<<"$CMD" | grep -oE '^[[:space:]]*cd[[:space:]]+[^[:space:];&|]+' | awk '{print $2}'; } )
  while IFS= read -r T; do
    T=${T/#\~/$HOME}; T=${T%\"}; T=${T#\"}
    case "$T" in /*) ;; ?*) T="$CWD/$T" ;; esac
    [ -n "$T" ] && [ -d "$T" ] && { DIR=$T; break; }
  done <<<"$CANDS"
fi
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$ROOT/.claude/hooks-off" ] && { log bypass "$ROOT"; exit 0; }
# The dev-skill repo is not gated by the pipeline it defines (its CLAUDE.md, 2026-09-13).
SELF=$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/.." && pwd -P)
[ "$(cd "$ROOT" && pwd -P)" = "$SELF" ] && { log self "$ROOT"; exit 0; }
# Installed as a PLUGIN, SELF is the cache copy, so the path above never matches the working repo
# and the admin rule silently stopped applying (2026-09-20, first write after the plugin install).
# Identity, not path: the source repo is the one declaring the same plugin as the copy this hook
# ships in.
SELF_PLUGIN=$(jq -r '.name // empty' "$SELF/.claude-plugin/plugin.json" 2>/dev/null)
ROOT_PLUGIN=$(jq -r '.name // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
[ -n "$SELF_PLUGIN" ] && [ "$SELF_PLUGIN" = "$ROOT_PLUGIN" ] && { log self "$ROOT"; exit 0; }

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
