#!/usr/bin/env bash
# Phase 1 — Context Load. SessionStart: stdout is added to the session context.
set -uo pipefail

HOOKDIR="$HOME/.claude/hooks"
log(){ printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" context-load "$1" "${2:-}" >>"$HOOKDIR/fired.log"; }

# Keep the family's install root pointing at whichever copy is live. Every door reads
# `~/.claude/.dev-root/...`, and a PLUGIN install never creates `~/.claude/skills/dev` — 68 reads broke
# silently the first time one was installed (2026-09-20). Derived from $0, not CLAUDE_PLUGIN_ROOT,
# which the harness substitutes into hook commands but never exports to a tool call.
SELF=$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/.." && pwd -P)
[ -f "$SELF/SKILL.md" ] && [ "$(readlink "$HOME/.claude/.dev-root" 2>/dev/null)" != "$SELF" ] && {
  ln -sfn "$SELF" "$HOME/.claude/.dev-root" && log root "$SELF"
}

IN=$(cat)
CWD=$(jq -r '.cwd // ""' <<<"$IN")
[ -n "$CWD" ] || exit 0
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT=$CWD
MAP="$ROOT/PROJECT_MAP.md"
[ -f "$MAP" ] || { log skip no-map; exit 0; }

BR=$(git -C "$ROOT" branch --show-current 2>/dev/null)
printf '## Phase 1 — Context Load (hook)\nRepo: %s · Branch: %s\n\n' "$(basename "$ROOT")" "${BR:-?}"
sed -n '/^## TECH_STACK/,/^## SYSTEM_FLOW/p' "$MAP" | head -40
sed -n '/^## ORPHANS/,$p'                    "$MAP" | head -30
log pass "$ROOT"
