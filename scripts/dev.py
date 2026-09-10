#!/usr/bin/env python3
"""Deterministic half of the dev family: phase state and environment checks.

Optional by design — every door falls back to its prose algorithm when this is
absent. Stdlib only, so it runs wherever python3 does.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Tuple

STATE_DIR = ".dev"
BASE_CANDIDATES = ("staging", "develop", "main", "master")
MAX_PHASE = 16


# ---------------------------------------------------------------- git helpers

def run(args: List[str], cwd: Optional[str] = None) -> Tuple[int, str]:
    """Run a command, returning (exit code, stripped stdout); stderr is discarded."""
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    except (OSError, ValueError):
        return 1, ""
    return p.returncode, p.stdout.strip()


def repo_root(cwd: Optional[str] = None) -> Optional[str]:
    code, out = run(["git", "rev-parse", "--show-toplevel"], cwd)
    return out if code == 0 and out else None


def current_branch(cwd: Optional[str] = None) -> Optional[str]:
    code, out = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd)
    return out if code == 0 and out else None


def head_sha(cwd: Optional[str] = None) -> Optional[str]:
    code, out = run(["git", "rev-parse", "HEAD"], cwd)
    return out if code == 0 and out else None


def remote_slug(cwd: Optional[str] = None) -> Optional[str]:
    """Parse owner/repo from origin, handling both SSH and HTTPS remote forms."""
    code, url = run(["git", "remote", "get-url", "origin"], cwd)
    if code != 0 or not url:
        return None
    m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
    return m.group(1) if m else None


def resolve_base(cwd: Optional[str] = None) -> Optional[str]:
    """First of staging/develop/main/master that exists on origin; a runbook overrides this."""
    code, out = run(["git", "branch", "-r", "--format=%(refname:short)"], cwd)
    if code != 0:
        return None
    remote = {l.strip().split("/", 1)[1] for l in out.splitlines() if "/" in l}
    for name in BASE_CANDIDATES:
        if name in remote:
            return name
    return current_branch(cwd)


# --------------------------------------------------------------------- state

def slugify(branch: str) -> str:
    """Branch names carry slashes; a filename must not, or it silently nests directories."""
    return re.sub(r"[^A-Za-z0-9._-]", "-", branch)


def state_path(root: str, branch: str) -> str:
    return os.path.join(root, STATE_DIR, slugify(branch) + ".json")


def load_state(root: str, branch: str) -> Optional[Dict]:
    path = state_path(root, branch)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def save_state(root: str, branch: str, data: Dict) -> str:
    path = state_path(root, branch)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return path


def phase_group(phase: int) -> str:
    """Coarse axis shown on a board card: phases 1-8 plan, 9-10 code, 11-13 validate."""
    if phase <= 8:
        return "planning"
    if phase <= 10:
        return "coding"
    if phase <= 13:
        return "validation"
    return "review"


def now() -> str:
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


# ------------------------------------------------------------------ commands

def cmd_checkpoint(args) -> int:
    root = repo_root()
    branch = current_branch()
    if not root or not branch:
        print("not a git repository", file=sys.stderr)
        return 2
    if not 0 <= args.phase <= MAX_PHASE:
        print("phase must be 0-%d" % MAX_PHASE, file=sys.stderr)
        return 2

    data = load_state(root, branch) or {
        "repo": remote_slug(),
        "branch": branch,
        "base": resolve_base(),
        "tier": None,
        "phase": None,
        "phases_completed": [],
        "attempts": [],
    }
    data["phase"] = args.phase
    data["phase_group"] = phase_group(args.phase)
    data["head_sha"] = head_sha()
    data["updated_at"] = now()
    if args.tier:
        data["tier"] = args.tier
    if args.phase not in data["phases_completed"]:
        data["phases_completed"] = sorted(set(data["phases_completed"]) | {args.phase})
    if args.attempt:
        data["attempts"].append({
            "phase": args.phase,
            "approach": args.attempt,
            "outcome": args.outcome or "unknown",
            "at": data["updated_at"],
        })

    path = save_state(root, branch, data)
    print("%s  phase %d (%s)" % (os.path.relpath(path, root), args.phase, data["phase_group"]))
    return 0


def cmd_read(args) -> int:
    root = repo_root()
    branch = args.branch or current_branch()
    if not root or not branch:
        print("not a git repository", file=sys.stderr)
        return 2
    data = load_state(root, branch)
    if data is None:
        print("no state for %s" % branch, file=sys.stderr)
        return 1
    print(json.dumps(data, indent=2, sort_keys=True))
    return 0


def cmd_verify(args) -> int:
    """Advisory state is only useful if it can be caught lying; git is the authority."""
    root = repo_root()
    branch = current_branch()
    if not root or not branch:
        print("not a git repository", file=sys.stderr)
        return 2
    data = load_state(root, branch)
    if data is None:
        print("MISSING  no state file for %s" % branch)
        return 1

    problems = []
    if data.get("branch") != branch:
        problems.append("branch: state says %r, git says %r" % (data.get("branch"), branch))
    live = head_sha()
    if data.get("head_sha") != live:
        problems.append("head_sha: state says %s, git says %s"
                        % (str(data.get("head_sha"))[:12], str(live)[:12]))
    if problems:
        for p in problems:
            print("STALE    " + p)
        return 1
    print("OK       %s at phase %s (%s)" % (branch, data.get("phase"), data.get("phase_group")))
    return 0


def _gitignore_covers_state(root: str) -> bool:
    code, _ = run(["git", "check-ignore", "-q", os.path.join(STATE_DIR, "x.json")], root)
    return code == 0


def cmd_doctor(args) -> int:
    """Report environment readiness; never repairs another repo on its own initiative."""
    rows = []
    root = repo_root()
    rows.append(("git repo", bool(root), root or "not inside a git repository"))

    if root:
        rows.append(("origin", bool(remote_slug()), remote_slug() or "no origin remote"))
        rows.append(("base branch", bool(resolve_base()), resolve_base() or "unresolved"))
        ignored = _gitignore_covers_state(root)
        rows.append((".dev/ ignored", ignored,
                     "yes" if ignored else "NOT ignored — add '%s/' to .gitignore" % STATE_DIR))

    code, out = run(["gh", "auth", "status"])
    rows.append(("gh auth", code == 0, "authenticated" if code == 0 else "gh missing or logged out"))

    ok_py = sys.version_info >= (3, 8)
    rows.append(("python", ok_py, sys.version.split()[0]))

    skill_root = os.path.expanduser("~/.claude/skills/dev")
    have_skill = os.path.isdir(skill_root)
    rows.append(("skill root", have_skill,
                 skill_root if have_skill else "not installed — run install.sh"))

    failed = 0
    for name, ok, detail in rows:
        if not ok:
            failed += 1
        print("%-15s %-4s %s" % (name, "ok" if ok else "WARN", detail))
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dev", description="dev family deterministic helpers")
    sub = p.add_subparsers(dest="group", required=True)

    state = sub.add_parser("state", help="phase state for the current branch")
    ssub = state.add_subparsers(dest="action", required=True)

    cp = ssub.add_parser("checkpoint", help="record the phase just completed")
    cp.add_argument("--phase", type=int, required=True)
    cp.add_argument("--tier", choices=["light", "standard", "deep"])
    cp.add_argument("--attempt", help="what was tried, recorded in attempts[]")
    cp.add_argument("--outcome", choices=["success", "failure"])
    cp.set_defaults(func=cmd_checkpoint)

    rd = ssub.add_parser("read", help="print the state file as JSON")
    rd.add_argument("--branch")
    rd.set_defaults(func=cmd_read)

    vf = ssub.add_parser("verify", help="fail if state disagrees with git")
    vf.set_defaults(func=cmd_verify)

    dr = sub.add_parser("doctor", help="check the environment this family needs")
    dr.set_defaults(func=cmd_doctor)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
