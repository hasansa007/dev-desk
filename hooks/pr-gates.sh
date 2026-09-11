#!/usr/bin/env bash
# Phases 12 / 14 / 16 — PR body sections, merges into prod, pushes onto protected refs.
# PreToolUse: Bash
set -uo pipefail

HOOKDIR="$HOME/.claude/hooks"
log(){ printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" pr-gates "$1" "${2:-}" >>"$HOOKDIR/fired.log"; }
deny(){ log deny "$1"; printf '%s\n' "$2" >&2; exit 2; }
ask(){ log ask "$1"; jq -nc --arg r "$2" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }

IN=$(cat)
CMD=$(jq -r '.tool_input.command // ""' <<<"$IN")
CWD=$(jq -r '.cwd // ""' <<<"$IN")
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT=$CWD
[ -f "$ROOT/.claude/hooks-off" ] && { log bypass "$ROOT"; exit 0; }

# ── Phases 12 + 14 — the PR body must carry ## PIPELINE and ## DOCS ───────────
if grep -qE '(^|[;&|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+create\b' <<<"$CMD"; then
  # A promotion PR (pre prod -> prod) carries already-reviewed commits rather than one branch's
  # work, so the sections belong on the feature PRs it is made of, not on it. Mirrors
  # ci/pr-gates.yml's `if: github.head_ref != 'staging'`, which this hook otherwise supersedes.
  HEAD_BR=$(grep -oE -- '--head[= ][^[:space:]]+' <<<"$CMD" | sed -E 's/^--head[= ]//' | tr -d "\"'")
  [ -n "$HEAD_BR" ] || HEAD_BR=$(git -C "$ROOT" branch --show-current 2>/dev/null)
  case "$HEAD_BR" in
    staging|pre-prod) log pass promotion-pr; HEAD_BR=skip ;;
    *) HEAD_BR=check ;;
  esac
fi
if [ "${HEAD_BR:-}" = "check" ]; then
  BF=$(grep -oE -- '--body-file[= ][^[:space:]]+' <<<"$CMD" | head -1 \
       | sed -E 's/^--body-file[= ]//' | tr -d "\"'")
  if [ -n "$BF" ]; then BODY=$(cat "${BF/#\~/$HOME}" 2>/dev/null) || BODY=""
  else BODY=$CMD; fi

  miss=()
  grep -qE '^## PIPELINE([[:space:]]|$)' <<<"$BODY" || miss+=("## PIPELINE")
  grep -qE '^## DOCS([[:space:]]|$)'     <<<"$BODY" || miss+=("## DOCS")
  if [ ${#miss[@]} -ne 0 ]; then
    deny create "PR body is missing: ${miss[*]}

## PIPELINE          (Phase 14)
Tier:    Light | Standard | Deep
Ran:     <phase numbers>
Skipped: <phase (reason)>   - a reason per phase, never a bare list
Gates:   <what each gate CAUGHT; \"clean\" is a result>

## DOCS              (Phase 12)
<ADRs/docs updated in THIS branch>   - or -
none needed - checked: no price/limit change, no decision-with-alternative,
no env/migration, no new module/flow, no deferred work, no doc made stale

override: touch \"$ROOT/.claude/hooks-off\"   (logged)"
  fi
  # Phase state, WHEN PRESENT, must agree with git. A PR carrying a false phase record is worse
  # than one carrying none, and this is the last moment being wrong costs anything.
  # Fires only on STALE: no .dev/ and no dev.py are the prose-fallback path, which must stay
  # silent or the CLI has stopped being optional. MISSING is not stale — it is unused.
  DEVPY="$HOME/.claude/skills/dev/scripts/dev.py"
  if [ -f "$DEVPY" ] && [ -d "$ROOT/.dev" ]; then
    SV=$(cd "$ROOT" && python3 "$DEVPY" state verify 2>&1)
    case "$SV" in
      STALE*) ask state-stale "Phase 14 - .dev/ phase state disagrees with git:

$SV

Git is authoritative; the state file is advisory. Re-checkpoint (dev state checkpoint --phase N)
or delete the stale file before opening a PR that reports a phase it cannot support." ;;
      *) log pass "state:${SV%% *}" ;;
    esac
  fi
  log pass create
fi

# ── Phase 16 — a merge into the prod branch approves the RELEASE ──────────────
if grep -qE '(^|[;&|])[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge\b' <<<"$CMD"; then
  N=$(grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+' <<<"$CMD" | grep -oE '[0-9]+$')
  BASE=$(cd "$ROOT" 2>/dev/null && gh pr view $N --json baseRefName -q .baseRefName 2>/dev/null)
  # Prod is not always called main. Treat the repo's DEFAULT branch as prod too.
  DEF=$(cd "$ROOT" 2>/dev/null && gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
  IS_PROD=no
  case "$BASE" in main|master) IS_PROD=yes ;; esac
  [ -n "$BASE" ] && [ "$BASE" = "$DEF" ] && IS_PROD=yes

  if [ -z "$BASE" ]; then
    ask merge-unknown "Phase 16 - could not read this PR's base branch. Confirm it is not the prod promotion."
  elif [ "$IS_PROD" = yes ]; then
    ask merge-prod "Phase 16 - this merges into '$BASE', which AUTO-DEPLOYS PROD. Secrets pre-flight run (skills/prod/prod-secrets.md)? Migrations already applied? Pre prod verified? This approves the RELEASE, not the work."
  else
    log pass "merge->$BASE"
  fi
fi

# ── Phases 12-14 — do not reach a protected ref by push ───────────────────────
PUSH=$(grep -oE '(^|[;&|])[[:space:]]*git[[:space:]]+push[^;&|]*' <<<"$CMD" | head -1)
if [ -n "$PUSH" ]; then
  if grep -qE 'origin/(main|master):(staging|pre-prod)' <<<"$PUSH"; then
    ask push-catchup "Documented catch-up (pipeline.md, Phase 16 - 'When the promotion merge auto-deploys') - fast-forwards pre prod to prod. Confirm."
  elif grep -qE '[[:space:]](origin[[:space:]]+)?(main|master|staging)([[:space:]]|$)|:(main|master|staging)([[:space:]]|$)' <<<"$PUSH"; then
    deny push "git push straight onto a protected ref bypasses Phases 12-14.
Open a PR instead - the docs and review gates live there.

override: touch \"$ROOT/.claude/hooks-off\"   (logged)"
  else
    log pass push
  fi
fi
exit 0
