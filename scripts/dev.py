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


# ---------------------------------------------------------------------- board

PRIORITY_ORDER = {"P1": 1, "P2": 2, "P3": 3}
UNPRIORITISED = 4
NO_SLICE = 9999

# A parent-child claim is a CHECKLIST line and nothing else. A bare `#N` grep also matches prose
# ("see the Roadmap issue #R"), which reported one epic as 1/5 when the truth was 0/4 — and a
# progress bar that is wrong is worse than none, because it is the number you plan from.
TASK_LINE = re.compile(r"^[ \t]*[-*][ \t]*\[([ xX])\][ \t]*#(\d+)", re.MULTILINE)
SLICE_RE = re.compile(r"\bslice[ \t]+(\d+)\b", re.IGNORECASE)


def parse_epic_children(body: str) -> List[Tuple[int, bool]]:
    """Children are the task-list lines; every other #N in the body is prose."""
    if not body:
        return []
    return [(int(n), c.lower() == "x") for c, n in TASK_LINE.findall(body)]


def epic_progress(children: List[Tuple[int, bool]]) -> Tuple[int, int]:
    """Progress counts closed over ALL children — 3/4 reads nothing like '1 open'."""
    return sum(1 for _, done in children if done), len(children)


def label_names(issue: Dict) -> List[str]:
    return [l.get("name", "") if isinstance(l, dict) else str(l) for l in issue.get("labels", [])]


def priority_rank(issue: Dict) -> int:
    """Unlabelled sorts AFTER P3: unprioritised is not urgent, and promoting it silently would
    make the label meaningless."""
    for name in label_names(issue):
        if name in PRIORITY_ORDER:
            return PRIORITY_ORDER[name]
    return UNPRIORITISED


def slice_rank(issue: Dict) -> int:
    """Slice numbering is a dependency statement, so N+1 never precedes N."""
    m = SLICE_RE.search(issue.get("title", "") or "")
    return int(m.group(1)) if m else NO_SLICE


def is_startable(issue: Dict, open_children: int) -> bool:
    """An epic parent with open children is already decomposed; offer a child instead."""
    if "epic" in label_names(issue) and open_children > 0:
        return False
    return True


def order_next(issues: List[Dict]) -> List[Dict]:
    """Priority, then slice, then the thing ignored longest."""
    return sorted(issues, key=lambda i: (priority_rank(i), slice_rank(i),
                                         i.get("updatedAt", ""), i.get("number", 0)))


def classify(issue: Dict, facts: Dict, active_milestone: Optional[str] = None) -> str:
    """Column for one open issue. Git-derived wherever git can see it."""
    if "epic-leftover" in label_names(issue):
        return "deferred"
    pr = facts.get("pr")
    if pr and pr.get("state") == "OPEN":
        if pr.get("reviewDecision") in ("REVIEW_REQUIRED", "CHANGES_REQUESTED", "APPROVED"):
            return "human_review"
        return "pr_created"
    if facts.get("unmerged", 0) > 0:
        return "in_progress"
    milestone = issue.get("milestone") or {}
    name = milestone.get("title") if isinstance(milestone, dict) else milestone
    if active_milestone and name == active_milestone:
        return "queue"
    return "backlog"


def build_board(issues: List[Dict], facts: Dict[int, Dict],
                active_milestone: Optional[str] = None) -> Dict:
    """Pure: issues + per-issue git facts in, columns out. All I/O happens in the caller."""
    columns: Dict[str, List[Dict]] = {
        "queue": [], "in_progress": [], "pr_created": [], "human_review": [],
        "backlog": [], "deferred": [],
    }
    epics = []
    for issue in issues:
        n = issue.get("number")
        f = facts.get(n, {})
        col = classify(issue, f, active_milestone)
        row = {"number": n, "title": issue.get("title", ""),
               "priority": priority_rank(issue), "column": col}
        if f.get("phase_group"):
            row["phase"] = f["phase_group"]
            row["phase_advisory"] = True
        if "epic" in label_names(issue):
            children = parse_epic_children(issue.get("body", ""))
            done, total = epic_progress(children)
            open_children = total - done
            row["epic"] = {"done": done, "total": total,
                           "startable": is_startable(issue, open_children)}
            epics.append(row)
            if not row["epic"]["startable"] and col == "backlog":
                continue  # shown as progress, never offered as work
        columns[col].append(row)

    columns["backlog"] = order_next(columns["backlog"])
    return {"columns": columns, "epics": epics,
            "counts": {k: len(v) for k, v in columns.items()}}


def _gh_json(args: List[str]) -> Optional[object]:
    code, out = run(["gh"] + args)
    if code != 0 or not out:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def cmd_board(args) -> int:
    root = repo_root()
    if not root:
        print("not a git repository", file=sys.stderr)
        return 2
    issues = _gh_json(["issue", "list", "--state", "open", "--limit", str(args.limit),
                       "--json", "number,title,labels,updatedAt,milestone,body"])
    if issues is None:
        # An auth failure and an empty tracker must never render the same.
        print("could not read issues — is gh authenticated for this repo?", file=sys.stderr)
        return 2

    base = resolve_base()
    facts: Dict[int, Dict] = {}
    code, out = run(["git", "branch", "--format=%(refname:short)"])
    branches = out.splitlines() if code == 0 else []
    for issue in issues:
        n = issue["number"]
        match = next((b for b in branches
                      if re.match(r"^(gh-)?%d(-|$)" % n, b) or ("/%d-" % n) in b), None)
        f: Dict = {}
        if match and base:
            c, cnt = run(["git", "rev-list", "--count", "%s..%s" % (base, match)])
            # A branch existing proves nothing; only unmerged commits do.
            f["unmerged"] = int(cnt) if c == 0 and cnt.isdigit() else 0
            st = load_state(root, match)
            if st:
                f["phase_group"] = st.get("phase_group")
        facts[n] = f

    board = build_board(issues, facts, args.milestone)
    if args.json:
        print(json.dumps(board, indent=2, sort_keys=True))
        return 0

    slug = remote_slug() or os.path.basename(root)
    # A partial count reported as the total is a number someone would plan from.
    truncated = " (TRUNCATED at --limit; the real total is higher)" if len(issues) >= args.limit else ""
    print("## %s — %d open%s" % (slug, len(issues), truncated))
    for col in ("queue", "in_progress", "pr_created", "human_review", "backlog", "deferred"):
        rows = board["columns"][col]
        if not rows:
            continue
        print("\n%s (%d)" % (col.upper().replace("_", " "), len(rows)))
        for r in rows[: args.top if col == "backlog" else len(rows)]:
            ph = "  [%s]" % r["phase"] if r.get("phase") else ""
            print("  #%-5s %s%s" % (r["number"], r["title"][:64], ph))
    for e in board["epics"]:
        ep = e["epic"]
        mark = "" if ep["startable"] else "  (children open — start a child)"
        print("\nepic #%s %s  %d/%d%s" % (e["number"], e["title"][:48],
                                          ep["done"], ep["total"], mark))
    return 0


# ------------------------------------------------------------------ dispatch

# Only invocations verified against an installed CLI belong here. A guessed flag produces a command
# that fails in CI at the least convenient moment, so an unknown agent is refused, never improvised.
AGENTS = {
    "claude": ["claude", "-p"],        # verified 2026-09-10, Claude Code 2.1.267
    "codex": ["codex", "exec"],        # verified 2026-09-10
}
UNSUPPORTED = {
    "antigravity": "a PATH shim reports the real CLI is not installed",
    "gemini": "no non-interactive invocation confirmed",
}


def skill_root() -> str:
    """Where the family is installed, not where it was cloned — see SKILL.md."""
    return os.path.expanduser("~/.claude/skills/dev")


def resolve_door(root: str, door: Optional[str]) -> Optional[str]:
    """`dev` is the root SKILL.md; anything else is a member door."""
    path = os.path.join(root, "SKILL.md") if door in (None, "dev") \
        else os.path.join(root, "skills", door, "SKILL.md")
    return path if os.path.isfile(path) else None


def list_doors(root: str) -> List[str]:
    """A door is a directory holding a SKILL.md — .DS_Store is not a door."""
    skills = os.path.join(root, "skills")
    if not os.path.isdir(skills):
        return []
    return sorted(d for d in os.listdir(skills)
                  if os.path.isfile(os.path.join(skills, d, "SKILL.md")))


def available_agents() -> List[str]:
    return [name for name in AGENTS if run(["command", "-v", name])[0] == 0
            or _which(name)]


def _which(name: str) -> bool:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if d and os.path.isfile(os.path.join(d, name)):
            return True
    return False


def build_prompt(door_path: str, door: str, args: List[str]) -> str:
    extra = (" Arguments: " + " ".join(args)) if args else ""
    return ("Read %s and execute it exactly as written, following every phase and gate it "
            "defines.%s" % (door_path, extra))


def build_command(agent: str, prompt: str) -> List[str]:
    return AGENTS[agent] + [prompt]


def cmd_run(args) -> int:
    root = skill_root()
    if not os.path.isdir(root):
        print("skill root not found at %s — run install.sh" % root, file=sys.stderr)
        return 2
    door_path = resolve_door(root, args.door)
    if not door_path:
        print("no such door: %s\navailable: dev, %s" % (args.door, ", ".join(list_doors(root))),
              file=sys.stderr)
        return 2

    agent = args.agent
    if agent in UNSUPPORTED:
        print("%s is not supported: %s" % (agent, UNSUPPORTED[agent]), file=sys.stderr)
        return 2
    if agent is None:
        found = available_agents()
        if not found:
            print("no supported agent CLI on PATH (%s)" % ", ".join(sorted(AGENTS)), file=sys.stderr)
            return 2
        agent = found[0]

    cmd = build_command(agent, build_prompt(door_path, args.door or "dev", args.args))
    printable = " ".join(cmd[:-1] + ['"%s"' % cmd[-1]])
    if not args.execute:
        # Dry run is the DEFAULT: this spawns an agent that can write to the repo, and a command
        # printed for review is useful, while one run by surprise is not.
        print(printable)
        print("\n(dry run — add --execute to actually dispatch)")
        return 0
    print("dispatching: %s" % printable, file=sys.stderr)
    try:
        return subprocess.run(cmd).returncode
    except OSError as e:
        print("could not start %s: %s" % (agent, e), file=sys.stderr)
        return 2


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

    bd = sub.add_parser("board", help="classify open issues into columns")
    bd.add_argument("--json", action="store_true")
    bd.add_argument("--limit", type=int, default=200)
    bd.add_argument("--top", type=int, default=3, help="backlog rows to show")
    bd.add_argument("--milestone", help="the active milestone; its members are the queue")
    bd.set_defaults(func=cmd_board)

    rn = sub.add_parser("run", help="dispatch a door to an agent CLI (dry run by default)")
    rn.add_argument("door", nargs="?", help="door name, or 'dev' for the full pipeline")
    rn.add_argument("args", nargs="*", help="arguments passed to the door")
    rn.add_argument("--agent", choices=sorted(list(AGENTS) + list(UNSUPPORTED)))
    rn.add_argument("--execute", action="store_true", help="actually dispatch")
    rn.set_defaults(func=cmd_run)

    dr = sub.add_parser("doctor", help="check the environment this family needs")
    dr.set_defaults(func=cmd_doctor)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
