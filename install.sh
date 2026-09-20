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

# Claude Code can install this repo as a PLUGIN, which carries the hooks the symlink cannot.
# Both at once means every door twice, so the symlink stands aside when the plugin is there.
plugin_installed() {
  local reg="$HOME/.claude/plugins/installed_plugins.json"
  [ -f "$reg" ] || return 1
  python3 -c "import json;print(any(k.split('@')[0]=='$NAME' for k in json.load(open('$reg')).get('plugins',{})))" 2>/dev/null | grep -q True
}

declare -a NAMES=(claude codex antigravity)
declare -a DIRS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$(agy_path || echo "$HOME/.agents/skills")")

ok=0; skip=0; same=0
for i in "${!NAMES[@]}"; do
  cli="${NAMES[$i]}"; dir="${DIRS[$i]}"; link="$dir/$NAME"
  if [ "$cli" = claude ] && plugin_installed; then
    printf '  %-12s installed as a plugin — skipped (the plugin carries the hooks too)\n' "$cli"
    skip=$((skip+1)); continue
  fi
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

# The family's install ROOT, which every door reads as `~/.claude/.dev-root/...`. Kept outside
# `skills/` on purpose: a root under `skills/` is scanned, and would list every door a second time
# alongside the plugin. The plugin maintains the same link from its SessionStart hook.
mkdir -p "$HOME/.claude" 2>/dev/null
ln -sfn "$SRC" "$HOME/.claude/.dev-root" 2>/dev/null \
  && printf '  %-12s root    %s\n' "dev root" "$HOME/.claude/.dev-root"

# The `dev` command: link scripts/dev.py into the first user bin dir ALREADY on PATH.
# Never edits a shell profile, never adds a PATH entry, never replaces something that is not ours —
# a `dev` belonging to another tool is reported and left alone.
link_dev_command() {
  local target="$SRC/scripts/dev.py" existing
  existing="$(command -v dev 2>/dev/null || true)"
  for b in "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$b:"*) ;; *) continue ;; esac
    [ -d "$b" ] && [ -w "$b" ] || continue
    local t="$b/dev"
    if [ -L "$t" ] && [ "$(readlink "$t")" = "$target" ]; then
      printf '  %-12s already linked, unchanged\n' "dev command"; return
    fi
    if [ -e "$t" ] || [ -L "$t" ]; then
      printf '  %-12s SKIPPED — %s exists and is not this family'"'"'s\n' "dev command" "$t"; return
    fi
    if [ -n "$existing" ]; then
      printf '  %-12s SKIPPED — another `dev` is already on PATH at %s\n' "dev command" "$existing"; return
    fi
    ln -s "$target" "$t" && printf '  %-12s linked  %s\n' "dev command" "$t"; return
  done
  printf '  %-12s not linked — no writable ~/.local/bin or ~/bin on PATH\n' "dev command"
  printf '               add to your shell profile: alias dev='"'"'python3 %s'"'"'\n' "$target"
}
link_dev_command

echo
echo "done: $ok installed, $same already linked, $skip skipped"
[ $ok -gt 0 ] && echo "reload with /reload-skills (claude) or restart the CLI"
exit 0
