#!/usr/bin/env bash
# Install this family into every agent CLI on the machine that uses the
# skills/<name>/SKILL.md convention. Skips what is not installed; never creates a
# config tree for a CLI that is absent; never overwrites a real directory.
#
# Installs THIS repo only. To install a sibling skill, run its own installer.
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The link name is FIXED to this repo's own name. It used to take $1, which let
# `install.sh archify` link archify -> dev-skill and clobber a correct symlink.
# A script that installs the repo it lives in has no business naming another.
NAME="dev"

# antigravity registers its skills path in config, so read it rather than assume.
agy_path() {
  local j="$HOME/.gemini/config/skills.json"
  [ -f "$j" ] || return 1
  python3 -c "import json,sys;print(json.load(open('$j'))['entries'][0]['path'])" 2>/dev/null
}

declare -a NAMES=(claude codex antigravity)
declare -a DIRS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$(agy_path || echo "$HOME/.agents/skills")")

ok=0; skip=0; same=0
for i in "${!NAMES[@]}"; do
  cli="${NAMES[$i]}"; dir="${DIRS[$i]}"; link="$dir/$NAME"
  if [ ! -d "$dir" ]; then
    printf '  %-12s not found — skipped\n' "$cli"; skip=$((skip+1)); continue
  fi
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$SRC" ]; then
    printf '  %-12s already linked, unchanged\n' "$cli"; same=$((same+1)); continue
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    printf '  %-12s SKIPPED — %s exists and is not a symlink\n' "$cli" "$link"; skip=$((skip+1)); continue
  fi
  ln -sfn "$SRC" "$link" && printf '  %-12s linked  %s\n' "$cli" "$link" && ok=$((ok+1))
done

echo
echo "done: $ok installed, $same already linked, $skip skipped"
[ $ok -gt 0 ] && echo "reload with /reload-skills (claude) or restart the CLI"
exit 0
