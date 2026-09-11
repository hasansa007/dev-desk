#!/usr/bin/env python3
"""Deterministic half of the dev family: phase state and environment checks.

Optional by design — every door falls back to its prose algorithm when this is
absent. Stdlib only, so it runs wherever python3 does.
"""

import argparse
import hmac
import json
import os
import re
import secrets
import shutil
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


def ensure_dev_dir(root: str) -> str:
    """Create .dev/ with its own `*` ignore — inside our folder, so the repo's .gitignore is never touched."""
    d = os.path.join(root, STATE_DIR)
    os.makedirs(d, exist_ok=True)
    ignore = os.path.join(d, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as fh:
            fh.write("# written by dev — everything here is generated or machine-local\n*\n")
    return d


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
    ensure_dev_dir(root)
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


# ------------------------------------------------- GitHub Projects v2 adapter

# The board MIRRORS; it never decides. Columns are computed from git and gh, then pushed here.
# Project status is never read back as truth — a stored value that can disagree with git is exactly
# the class of bug the precedence rule exists to prevent.
STATUS_CANDIDATES = {
    "backlog": ["backlog", "todo", "to do", "no status"],
    # deliberately NOT "todo": that is backlog's option, and silently merging two columns
    # into one loses the queue/backlog distinction the milestone design exists for.
    # Unmapped is reported; a silent merge is not.
    "queue": ["queue", "queued", "ready", "next", "up next"],
    "in_progress": ["in progress", "in-progress", "doing", "wip"],
    "pr_created": ["in review", "review", "pr open"],
    "human_review": ["in review", "review", "needs review"],
    "done": ["done", "closed", "shipped"],
    "deferred": ["blocked", "deferred", "on hold", "icebox"],
}


def find_status_field(fields: List[Dict]) -> Optional[Dict]:
    """The single-select field a Project uses for columns; GitHub names it Status by default."""
    for f in fields:
        if f.get("type") == "ProjectV2SingleSelectField" and f.get("name", "").lower() == "status":
            return f
    for f in fields:
        if f.get("type") == "ProjectV2SingleSelectField":
            return f
    return None


def match_option(column: str, options: List[Dict]) -> Optional[Dict]:
    """Map one of our columns onto a Status option by name. Never invents an option."""
    by_name = {o.get("name", "").strip().lower(): o for o in options}
    for candidate in STATUS_CANDIDATES.get(column, []):
        if candidate in by_name:
            return by_name[candidate]
    return None


def plan_project_sync(board: Dict, items: List[Dict], options: List[Dict]) -> Dict:
    """Pure: computed board + current project items in, the edits needed out.

    Returns `edits` (item id → option), `unmapped` (columns with no matching option), and
    `absent` (issues on the board that are not items in the project).
    """
    want: Dict[int, str] = {}
    for column, rows in board.get("columns", {}).items():
        for row in rows:
            want[row["number"]] = column

    by_number = {}
    for it in items:
        content = it.get("content") or {}
        n = content.get("number")
        if n is not None:
            by_number[n] = it

    edits, unmapped, absent = [], set(), []
    for number, column in sorted(want.items()):
        item = by_number.get(number)
        if item is None:
            absent.append(number)
            continue
        option = match_option(column, options)
        if option is None:
            unmapped.add(column)
            continue
        if (item.get("status") or "").strip().lower() != option["name"].strip().lower():
            edits.append({"number": number, "item_id": item.get("id"),
                          "from": item.get("status") or "(none)",
                          "to": option["name"], "option_id": option.get("id")})
    return {"edits": edits, "unmapped": sorted(unmapped), "absent": absent}


def cmd_project(args) -> int:
    root = repo_root()
    if not root:
        print("not a git repository", file=sys.stderr)
        return 2
    slug = remote_slug()
    owner = slug.split("/")[0] if slug else None
    if not owner:
        print("no origin remote — cannot resolve the project owner", file=sys.stderr)
        return 2

    projects = _gh_json(["project", "list", "--owner", owner, "--format", "json"])
    if projects is None:
        # The scope is the usual cause and the message must say so, not read as "no projects".
        print("could not list projects for %s.\n"
              "If this is a scope problem: gh auth refresh -s project\n"
              "The board works without a project — this adapter is optional." % owner,
              file=sys.stderr)
        return 2
    plist = projects.get("projects", projects if isinstance(projects, list) else [])
    if not plist:
        print("%s has no Projects v2 boards. Nothing to mirror to." % owner)
        return 0
    if args.number is None:
        for p in plist:
            print("  #%-4s %-40s %s items" % (p.get("number"), p.get("title", "")[:40],
                                              p.get("items", {}).get("totalCount", "?")))
        print("\npick one with --number N")
        return 0

    fields = _gh_json(["project", "field-list", str(args.number), "--owner", owner,
                       "--format", "json"]) or {}
    status = find_status_field(fields.get("fields", []))
    if status is None:
        print("project #%s has no single-select Status field to mirror into" % args.number,
              file=sys.stderr)
        return 2
    items = _gh_json(["project", "item-list", str(args.number), "--owner", owner,
                      "--format", "json"]) or {}

    board = build_board(_gh_json(["issue", "list", "--state", "open", "--limit", "200", "--json",
                                  "number,title,labels,updatedAt,milestone,body"]) or [], {},
                        args.milestone)
    plan = plan_project_sync(board, items.get("items", []), status.get("options", []))

    for e in plan["edits"]:
        print("  #%-5s %-14s → %s" % (e["number"], e["from"], e["to"]))
    for c in plan["unmapped"]:
        print("  column %r has no matching Status option — not guessing one" % c, file=sys.stderr)
    if plan["absent"]:
        print("  not in the project: %s" % ", ".join("#%d" % n for n in plan["absent"]))
    if not plan["edits"]:
        print("  project already matches the computed board")
        return 0
    if not args.apply:
        print("\n(dry run — add --apply to write %d change(s) to the project)" % len(plan["edits"]))
        return 0

    pid = next((p.get("id") for p in plist if str(p.get("number")) == str(args.number)), None)
    failed = 0
    for e in plan["edits"]:
        code, _ = run(["gh", "project", "item-edit", "--id", e["item_id"], "--project-id", pid,
                       "--field-id", status.get("id"),
                       "--single-select-option-id", e["option_id"]])
        if code != 0:
            print("  FAILED #%s" % e["number"], file=sys.stderr)
            failed += 1
    print("  wrote %d, failed %d" % (len(plan["edits"]) - failed, failed))
    return 1 if failed else 0



# ------------------------------------------------------------------------ ui

# .dev/ui/ is GENERATED OUTPUT, never an input. Nothing in this family reads it back — it is a snapshot
# of what the doors computed, the same relationship docs/arch/*.html has to its IR. Every file
# carries the commit it was built from, so a stale one is visible rather than assumed fresh.
UI_DIR = os.path.join(STATE_DIR, "ui")
UI_SURFACES = ("board", "roadmap", "ideation", "insights")
UI_PREVIEW_LINES = 8  # a section's first lines stay visible; the rest fold, never cut


def _headings(md: str) -> List[Dict]:
    """Split a markdown document on its ## headings. Structure only — never interprets prose."""
    out, current = [], None
    for line in md.splitlines():
        if line.startswith("## "):
            current = {"heading": line[3:].strip(), "lines": []}
            out.append(current)
        elif current is not None and line.strip():
            current["lines"].append(line.rstrip())
    return out


def collect_board(root: str, milestone: Optional[str] = None) -> Dict:
    issues = _gh_json(["issue", "list", "--state", "open", "--limit", "200",
                       "--json", "number,title,labels,updatedAt,milestone,body"])
    if issues is None:
        return {"unavailable": "could not read issues — is gh authenticated?"}
    why = "given with --milestone" if milestone else None
    if not milestone:
        milestone, why = resolve_active_milestone(_open_milestones() or [])
    facts: Dict[int, Dict] = {}
    base = resolve_base()
    code, out = run(["git", "branch", "--format=%(refname:short)"])
    branches = out.splitlines() if code == 0 else []
    for issue in issues:
        n = issue["number"]
        match = next((b for b in branches
                      if re.match(r"^(gh-)?%d(-|$)" % n, b) or ("/%d-" % n) in b), None)
        f: Dict = {}
        if match and base:
            c, cnt = run(["git", "rev-list", "--count", "%s..%s" % (base, match)])
            f["unmerged"] = int(cnt) if c == 0 and cnt.isdigit() else 0
            st = load_state(root, match)
            if st:
                f["phase_group"] = st.get("phase_group")
        facts[n] = f
    board = build_board(issues, facts, milestone)
    board["active_milestone"], board["active_why"] = milestone, why
    return board


def _open_milestones() -> Optional[List[Dict]]:
    return _gh_json(["api", "repos/%s/milestones?state=open" % (remote_slug() or "/"),
                     "--jq", "[.[] | {title, due_on, created_at}]"])


def resolve_active_milestone(milestones: List[Dict]) -> Tuple[Optional[str], str]:
    """dev:roadmap's rule: the open milestone due soonest, else the oldest open. A tie is never broken silently."""
    if not milestones:
        return None, "no open milestone; dev:roadmap sets one"
    dated = sorted((m for m in milestones if m.get("due_on")), key=lambda m: m["due_on"])
    if dated:
        if len(dated) > 1 and dated[0]["due_on"][:10] == dated[1]["due_on"][:10]:
            return None, ("%s and %s are due the same day — pass --milestone"
                          % (dated[0]["title"], dated[1]["title"]))
        return dated[0]["title"], "nearest due date (%s)" % dated[0]["due_on"][:10]
    oldest = min(milestones, key=lambda m: m.get("created_at") or "")
    return oldest["title"], "oldest open milestone; none has a due date"


def collect_roadmap() -> Dict:
    slug = remote_slug() or "/"
    ms = _gh_json(["api", "repos/%s/milestones" % slug,
                   "--jq", "[.[] | {title, open: .open_issues, closed: .closed_issues, due: .due_on}]"])
    if ms is None:
        return {"unavailable": "could not read milestones"}
    epics = _gh_json(["issue", "list", "--state", "open", "--label", "epic",
                      "--json", "number,title,milestone,body"]) or []
    for e in epics:
        done, total = epic_progress(parse_epic_children(e.get("body", "")))
        e["progress"] = {"done": done, "total": total}
        e.pop("body", None)
    return {"milestones": ms, "epics": epics}


def collect_reports(root: str, kind: str) -> Dict:
    """Structured output if the door wrote it; otherwise an index of the dated reports."""
    d = os.path.join(root, "docs", kind)
    if not os.path.isdir(d):
        return {"reports": [], "note": "no docs/%s/ yet — run dev:%s" % (kind, kind)}
    reports = []
    for name in sorted(os.listdir(d), reverse=True):
        path = os.path.join(d, name)
        if name.endswith(".json"):
            try:
                with open(path, encoding="utf-8") as fh:
                    reports.append({"file": name, "structured": True, "data": json.load(fh)})
                continue
            except (OSError, ValueError):
                pass
        if name.endswith(".md"):
            reports.append({"file": name, "structured": False,
                            "sections": [h["heading"] for h in
                                         _headings(open(path, encoding="utf-8").read())]})
    return {"reports": reports}


def collect_insights(root: str) -> Dict:
    p = os.path.join(root, "PROJECT_MAP.md")
    if not os.path.isfile(p):
        return {"unavailable": "no PROJECT_MAP.md — run dev:insights"}
    with open(p, encoding="utf-8") as fh:
        return {"sections": _headings(fh.read())}


def render_ui_html(surface: str, data: Dict, meta: Dict) -> str:
    """One self-contained file per surface. No network, no build step, no dependencies."""
    body = []
    if data.get("unavailable"):
        body.append('<p class="empty">%s</p>' % _esc(data["unavailable"]))
    elif surface == "board":
        ms = data.get("active_milestone")
        body.append('<p class="hint">%s</p>' % (
            "QUEUE = milestone <b>%s</b> — %s" % (_esc(ms), _esc(data.get("active_why") or ""))
            if ms else "QUEUE is empty — %s" % _esc(data.get("active_why") or "no active milestone")))
        body.append('<p class="hint" id="static-hint">Read-only file. Run <code>dev ui --serve</code>'
                    " to drag cards between QUEUE and BACKLOG.</p>")
        for col, rows in data.get("columns", {}).items():
            body.append('<section data-col="%s"><h2>%s <span class="n">%d</span></h2>'
                        % (_esc(col), _esc(col.replace("_", " ").upper()), len(rows)))
            body.append("".join(
                '<article data-n="%s" data-col="%s"%s><b>#%s</b> %s%s</article>'
                % (r["number"], _esc(col), ' data-epic="1"' if r.get("epic") else "",
                   r["number"], _esc(r["title"]),
                   '<em>%s · advisory</em>' % _esc(r["phase"]) if r.get("phase") else "")
                for r in rows) or '<p class="empty">nothing here</p>')
            body.append("</section>")
        body.append('<section data-col="cancel" hidden><h2>CANCEL</h2><p class="empty">drop here to'
                    " close as not planned — asks why, and posts it as the comment</p></section>")
        body.append(BOARD_DRAG_JS)
    elif surface == "roadmap":
        body.append('<section><h2>MILESTONES</h2>')
        body.append("".join('<article><b>%s</b> %s open / %s closed</article>'
                            % (_esc(m.get("title", "")), m.get("open"), m.get("closed"))
                            for m in data.get("milestones", [])) or '<p class="empty">none</p>')
        body.append('</section><section><h2>EPICS</h2>')
        body.append("".join('<article><b>#%s</b> %s <em>%s/%s</em></article>'
                            % (e["number"], _esc(e["title"]),
                               e["progress"]["done"], e["progress"]["total"])
                            for e in data.get("epics", [])) or '<p class="empty">none</p>')
        body.append("</section>")
    elif surface in ("ideation", "survey"):
        body.append('<section><h2>REPORTS</h2>')
        body.append("".join('<article><b>%s</b> <em>%s</em></article>'
                            % (_esc(r["file"]),
                               "structured" if r["structured"] else _esc(", ".join(r.get("sections", []))[:120]))
                            for r in data.get("reports", []))
                    or '<p class="empty">%s</p>' % _esc(data.get("note", "none")))
        body.append("</section>")
    else:
        for s in data.get("sections", []):
            shown, rest = s["lines"][:UI_PREVIEW_LINES], s["lines"][UI_PREVIEW_LINES:]
            fold = ('<details><summary>%d more lines</summary><pre>%s</pre></details>'
                    % (len(rest), _esc("\n".join(rest)))) if rest else ""
            body.append('<section><h2>%s</h2><pre>%s</pre>%s</section>'
                        % (_esc(s["heading"]), _esc("\n".join(shown)), fold))

    return UI_TEMPLATE % {
        "surface": _esc(surface),
        "nav": _ui_nav(surface),
        "repo": _esc(meta.get("repo") or ""),
        "commit": _esc((meta.get("commit") or "")[:8]),
        "at": _esc(meta.get("generated_at") or ""),
        "body": "".join(body),
    }


def _ui_nav(current: str) -> str:
    return "<nav>%s</nav>" % " ".join(
        '<a href="%s.html"%s>%s</a>' % (s, ' class="on"' if s == current else "", s)
        for s in ("index",) + UI_SURFACES)


def ui_summary(surface: str, data: Dict) -> str:
    """One line for the index card — counts only, read from the snapshot already on disk."""
    if data.get("unavailable"):
        return data["unavailable"]
    if surface == "board":
        cols = data.get("columns", {})
        return "%d open · %d columns" % (sum(len(r) for r in cols.values()), len(cols))
    if surface == "roadmap":
        return "%d milestones · %d epics" % (len(data.get("milestones", [])), len(data.get("epics", [])))
    if surface == "ideation":
        return data.get("note") or "%d reports" % len(data.get("reports", []))
    return "%d sections" % len(data.get("sections", []))


def render_ui_index(root: str, meta: Dict) -> str:
    cards = []
    for s in UI_SURFACES:
        try:
            with open(os.path.join(root, UI_DIR, s + ".json"), encoding="utf-8") as fh:
                snap = json.load(fh)
            line = "%s<em>built from %s · %s</em>" % (
                _esc(ui_summary(s, snap.get("data", {}))),
                _esc(str(snap.get("commit") or "")[:8]), _esc(snap.get("generated_at") or ""))
        except (OSError, ValueError):
            line = "not built yet<em>run <code>dev ui %s</code></em>" % s
        cards.append('<a class="card" href="%s.html"><section><h2>%s</h2><article>%s</article>'
                     "</section></a>" % (s, s.upper(), line))
    return UI_TEMPLATE % {"surface": "index", "nav": _ui_nav("index"),
                          "repo": _esc(meta.get("repo") or ""),
                          "commit": _esc((meta.get("commit") or "")[:8]),
                          "at": _esc(meta.get("generated_at") or ""), "body": "".join(cards)}


def _esc(s) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


# Inert unless `dev ui --serve` injected DEV_LIVE — a file:// page has no server to write through.
BOARD_DRAG_JS = """<script>
(function () {
  var live = window.DEV_LIVE;
  if (!live) return;
  document.getElementById('static-hint').textContent =
    'Drag between QUEUE and BACKLOG · drop on CANCEL to close as not planned · other columns follow git.';
  document.querySelector('section[data-col=cancel]').hidden = false;
  var MOVABLE = ['queue', 'backlog'], TARGETS = ['queue', 'backlog', 'cancel'];
  document.querySelectorAll('article[data-n]').forEach(function (a) {
    if (MOVABLE.indexOf(a.dataset.col) < 0) { a.title = 'this column follows git'; return; }
    a.draggable = true;
    a.classList.add('drag');
    a.addEventListener('dragstart', function (e) { e.dataTransfer.setData('text/plain', a.dataset.n); });
  });
  document.querySelectorAll('section[data-col]').forEach(function (s) {
    if (TARGETS.indexOf(s.dataset.col) < 0) return;
    s.addEventListener('dragover', function (e) { e.preventDefault(); s.classList.add('over'); });
    s.addEventListener('dragleave', function () { s.classList.remove('over'); });
    s.addEventListener('drop', function (e) {
      e.preventDefault();
      s.classList.remove('over');
      var n = e.dataTransfer.getData('text/plain'), to = s.dataset.col, reason = '';
      if (to === 'cancel') {
        reason = prompt('Close #' + n + ' as not planned. Why? (posted as the closing comment)');
        if (!reason || !reason.trim()) return;
      }
      fetch('/api/move', {method: 'POST',
        headers: {'Content-Type': 'application/json', 'X-Dev-Token': live.token},
        body: JSON.stringify({number: Number(n), to: to, reason: reason})})
        .then(function (r) { return r.json(); })
        .then(function (b) { if (b.ok) location.reload(); else alert(b.message); })
        .catch(function () { alert('the dev ui server stopped — run dev ui --serve again'); });
    });
  });
})();
</script>"""


UI_TEMPLATE = """<!doctype html>
<meta charset="utf-8"><title>dev · %(surface)s</title>
<style>
:root{color-scheme:dark}
body{margin:0;padding:2rem;background:#0d0f12;color:#e6e8eb;
     font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
header{display:flex;gap:1rem;align-items:baseline;margin-bottom:1.5rem}
h1{font-size:1.1rem;margin:0;color:#e9f07a}
.meta{color:#6b7280;font-size:.8rem}
.wrap{display:flex;gap:1rem;align-items:flex-start;flex-wrap:wrap}
section{flex:1 1 260px;min-width:260px;background:#14171c;border:1px solid #232830;
        border-radius:10px;padding:.75rem}
h2{font-size:.75rem;letter-spacing:.08em;color:#9aa3af;margin:0 0 .6rem}
.n{color:#6b7280}
article{background:#1a1e25;border:1px solid #232830;border-radius:7px;
        padding:.5rem .6rem;margin-bottom:.4rem}
article b{color:#e9f07a;font-weight:600}
article em{display:block;color:#6b7280;font-style:normal;font-size:.75rem;margin-top:.2rem}
.empty{color:#4b5563;font-size:.8rem;margin:.2rem 0}
pre{white-space:pre-wrap;color:#9aa3af;font-size:.78rem;margin:0}
details summary{cursor:pointer;color:#6b7280;font-size:.75rem;margin-top:.4rem}
details[open] summary{color:#e9f07a}
footer{margin-top:2rem;color:#4b5563;font-size:.75rem}
nav{margin-bottom:1.25rem;display:flex;gap:.4rem}
nav a{color:#9aa3af;text-decoration:none;padding:.2rem .6rem;border:1px solid #232830;border-radius:6px}
nav a.on,nav a:hover{color:#0d0f12;background:#e9f07a;border-color:#e9f07a}
a.card{flex:1 1 260px;color:inherit;text-decoration:none;display:flex}
a.card:hover section{border-color:#e9f07a}
.hint{flex:1 1 100%%;color:#6b7280;font-size:.8rem;margin:0}
.hint b{color:#e9f07a}
article.drag{cursor:grab}
section.over{border-color:#e9f07a}
section[data-col=cancel]{border-style:dashed;border-color:#7f1d1d}
</style>
<!--dev-live-->
%(nav)s
<header><h1>dev · %(surface)s</h1>
<span class="meta">%(repo)s · built from %(commit)s · %(at)s</span></header>
<div class="wrap">%(body)s</div>
<footer>Generated by <code>dev ui</code>. Never read back as truth — regenerate rather than trust.</footer>
"""


# board and roadmap read GitHub, which changes without a commit, so nothing local can prove them
# fresh — for those, "if needed" is always yes, and fetching to compare would cost as much as rebuilding.
UI_REMOTE = ("board", "roadmap")
REMOTE_REASON = "reads GitHub, which changes without a commit"


def ui_inputs(root: str, surface: str) -> List[str]:
    """The local files a surface is built from; a change to any of them makes it stale."""
    if surface == "insights":
        return [os.path.join(root, "PROJECT_MAP.md")]
    if surface == "ideation":
        d = os.path.join(root, "docs", "ideation")
        return [os.path.join(d, n) for n in os.listdir(d)] if os.path.isdir(d) else [d]
    return []


def ui_staleness(root: str, surface: str, head: Optional[str]) -> Optional[str]:
    """Why a surface must be rebuilt, or None when it is fresh — always a reason, never a bare flag."""
    path = os.path.join(root, UI_DIR, surface + ".json")
    if not os.path.isfile(path):
        return "missing"
    try:
        with open(path, encoding="utf-8") as fh:
            built_from = json.load(fh).get("commit")
    except (OSError, ValueError):
        return "unreadable"
    if not os.path.isfile(os.path.join(root, UI_DIR, surface + ".html")):
        return "html missing"
    if surface in UI_REMOTE:
        return REMOTE_REASON
    if built_from != head:
        return "built from %s, HEAD is %s" % (str(built_from)[:7], str(head)[:7])
    built_at = os.path.getmtime(path)
    for f in ui_inputs(root, surface):
        if os.path.exists(f) and os.path.getmtime(f) > built_at:
            return "%s changed since" % os.path.relpath(f, root)
    return None


def cmd_ui(args) -> int:
    root = repo_root()
    if not root:
        print("not a git repository", file=sys.stderr)
        return 2
    head = head_sha()
    check, force = getattr(args, "check", False), getattr(args, "force", False)
    surfaces = [args.surface] if args.surface else list(UI_SURFACES)
    out_dir = os.path.join(root, UI_DIR)

    if check:
        stale = 0
        for s in surfaces:
            why = ui_staleness(root, s, head)
            if why == REMOTE_REASON:
                # always refreshed, never "stale": counting it would make --check fail forever
                print("  %-9s live — rebuilt on every `dev ui` (%s)" % (s, why))
                continue
            stale += why is not None
            print("  %-9s %s" % (s, "stale — " + why if why else "fresh"))
        return 1 if stale else 0

    meta = {"repo": remote_slug(), "commit": head, "generated_at": now()}
    ensure_dev_dir(root)
    os.makedirs(out_dir, exist_ok=True)
    for s in surfaces:
        # a surface named explicitly is rebuilt; `dev ui` alone rebuilds only what is stale
        why = "requested" if (force or args.surface) else ui_staleness(root, s, head)
        if why is None:
            print("  %-9s fresh — skipped" % s)
            continue
        if s == "board":
            data = collect_board(root, args.milestone)
        elif s == "roadmap":
            data = collect_roadmap()
        elif s == "ideation":
            data = collect_reports(root, "ideation")
        else:
            data = collect_insights(root)
        write_ui_surface(root, s, data, meta)
        note = data.get("unavailable") or data.get("note") or "rebuilt — %s" % why
        print("  %-9s %s/%s.html  %s" % (s, UI_DIR, s, note))
    write_ui_index(root, meta)

    # pages used to live in <root>/ui/; only a folder holding OUR snapshot counts — src/ui/ is someone's code
    try:
        with open(os.path.join(root, "ui", "board.json"), encoding="utf-8") as fh:
            leftover = "surface" in json.load(fh)
    except (OSError, ValueError, TypeError):
        leftover = False
    if leftover:
        print("\nnote: ui/ at the repo root is a leftover from an older `dev ui` — the pages now live"
              "\n      in %s/. Nothing deletes it for you; remove ui/ when you like." % UI_DIR)

    first = os.path.join(out_dir, (surfaces[0] if args.surface else "index") + ".html")
    if getattr(args, "serve", False):
        server, _ = make_ui_server(root, getattr(args, "port", 0) or 0, args.milestone)
        url = "http://127.0.0.1:%d/%s" % (server.server_address[1], os.path.basename(first))
        print("\nserving %s — board cards can be dragged; every write is printed here. Ctrl-C stops."
              % url)
        if args.open:
            import webbrowser
            webbrowser.open(url)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
        return 0
    if args.open:
        # stdlib, so it works on macOS, Linux and Windows without a platform switch
        import webbrowser
        webbrowser.open("file://" + first)
        print("\nopened %s" % os.path.relpath(first, root))
    else:
        print("\n%s — add --open to launch it; regenerate, never edit by hand"
              % os.path.relpath(first, root))
    return 0


def write_ui_surface(root: str, surface: str, data: Dict, meta: Dict) -> None:
    out_dir = os.path.join(root, UI_DIR)
    payload = dict(meta, surface=surface, data=data)
    with open(os.path.join(out_dir, surface + ".json"), "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    with open(os.path.join(out_dir, surface + ".html"), "w", encoding="utf-8") as fh:
        fh.write(render_ui_html(surface, data, meta))


def write_ui_index(root: str, meta: Dict) -> None:
    # the index reads every snapshot on disk, so it is rebuilt whenever any page is
    with open(os.path.join(root, UI_DIR, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(render_ui_index(root, meta))


# ------------------------------------------------------------- ui --serve

# The served board turns a drag into dev:kanban Phase 7's MOVE or CANCEL tier — nothing more.
# The card's column is re-derived from gh on every request: the page is output, and a page that
# could say where a card is would make it an input. Delete is never offered here; 7.2 needs a human.
BOARD_MOVABLE = ("queue", "backlog")


def plan_board_move(card: Dict, target: str, active_milestone: Optional[str],
                    reason: str = "") -> Tuple[Optional[List[str]], str]:
    """A drag → one bounded gh write, or the reason it is refused."""
    n, col = str(card["number"]), card.get("column") or ""
    if col not in BOARD_MOVABLE:
        return None, ("#%s is in %s — that column is derived from git (or the epic-leftover label)"
                      " and moves when they do" % (n, col.replace("_", " ").upper()))
    if target == col:
        return None, "#%s is already in %s" % (n, col.upper())
    if target == "queue":
        if not active_milestone:
            return None, "no active milestone to queue into — set one with dev:roadmap or pass --milestone"
        return (["issue", "edit", n, "--milestone", active_milestone],
                "#%s → QUEUE (milestone %s)" % (n, active_milestone))
    if target == "backlog":
        return ["issue", "edit", n, "--remove-milestone"], "#%s → BACKLOG (milestone removed)" % n
    if target == "cancel":
        if card.get("epic"):
            return None, "#%s is an epic — its children need a decision first; cancel it through dev:kanban" % n
        if not reason.strip():
            return None, "cancel needs a reason — it is posted as the closing comment"
        return (["issue", "close", n, "--reason", "not planned", "--comment", reason.strip()],
                "#%s closed as not planned" % n)
    return None, "%s is not a board action — only QUEUE, BACKLOG and CANCEL are" % target


def _host_ok(headers, port: int) -> bool:
    # a rebinding attack reaches 127.0.0.1 but still sends its own Host
    return headers.get("Host", "") in ("127.0.0.1:%d" % port, "localhost:%d" % port)


def ui_request_allowed(headers, token: str, port: int) -> bool:
    """A write needs this machine AND a page this server handed the token to."""
    return _host_ok(headers, port) and hmac.compare_digest(headers.get("X-Dev-Token", ""), token)


def gh_write(argv: List[str]) -> Tuple[bool, str]:
    try:
        p = subprocess.run(["gh"] + argv, capture_output=True, text=True)
    except OSError as e:
        return False, str(e)
    return p.returncode == 0, (p.stderr or p.stdout).strip()


def make_ui_server(root: str, port: int, milestone: Optional[str]):
    """127.0.0.1 only. Serves the generated pages and one endpoint: POST /api/move."""
    import http.server
    token = secrets.token_urlsafe(24)
    pages = {"/": "index.html", "/index.html": "index.html"}
    pages.update({"/%s.html" % s: s + ".html" for s in UI_SURFACES})

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code: int, body: str, ctype: str = "application/json") -> None:
            data = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype + "; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _reply(self, code: int, ok: bool, message: str) -> None:
            self._send(code, json.dumps({"ok": ok, "message": message}))

        def do_GET(self):
            if not _host_ok(self.headers, self.server.server_address[1]):
                return self._send(403, "{}")
            name = pages.get(self.path.split("?")[0])
            path = os.path.join(root, UI_DIR, name) if name else ""
            if not name or not os.path.isfile(path):
                return self._send(404, "{}")
            with open(path, encoding="utf-8") as fh:
                html = fh.read().replace(
                    "<!--dev-live-->", "<script>window.DEV_LIVE={token:%s}</script>" % json.dumps(token))
            self._send(200, html, "text/html")

        def do_POST(self):
            if self.path != "/api/move":
                return self._send(404, "{}")
            if not ui_request_allowed(self.headers, token, self.server.server_address[1]):
                return self._reply(403, False, "refused — not from a page this server served")
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
                number, to = int(req["number"]), str(req["to"])
            except (ValueError, KeyError, TypeError):
                return self._reply(400, False, "expected {number, to}")
            board = collect_board(root, milestone)
            # the column is whichever list gh put the card in now — never what the page claims
            col, card = next(((k, c) for k, rows in board.get("columns", {}).items() for c in rows
                              if c.get("number") == number), (None, None))
            if card is None:
                return self._reply(409, False, "#%d is not an open card on this board" % number)
            argv, message = plan_board_move(dict(card, column=col), to, board.get("active_milestone"),
                                            str(req.get("reason") or ""))
            if argv is None:
                return self._reply(409, False, message)
            print("  %s%s" % (remote_slug(root) or "", message))  # state owner/repo#N out loud
            ok, err = gh_write(argv)
            if not ok:
                return self._reply(502, False, "gh refused: %s" % err)
            meta = {"repo": remote_slug(root), "commit": head_sha(root), "generated_at": now()}
            write_ui_surface(root, "board", collect_board(root, milestone), meta)
            write_ui_index(root, meta)
            self._reply(200, True, message)

    return http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler), token

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
    """`shutil.which`, not `command -v`: that is a shell builtin, and /usr/bin/command exists on
    macOS but not on the Linux runner CI uses — so the subprocess form works here and fails there."""
    return [name for name in AGENTS if shutil.which(name)]


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

    root_dir = skill_root()
    have_skill = os.path.isdir(root_dir)
    rows.append(("skill root", have_skill,
                 root_dir if have_skill else "not installed — run install.sh"))

    failed = 0
    for name, ok, detail in rows:
        if not ok:
            failed += 1
        print("%-15s %-4s %s" % (name, "ok" if ok else "WARN", detail))

    # Optional capabilities are REPORTED, never counted as failures — the family works without
    # every one of them, and a doctor that fails on an unused extra is a doctor people stop running.
    owner = (remote_slug() or "/").split("/")[0]
    has_projects = owner and run(["gh", "project", "list", "--owner", owner,
                                  "--format", "json"])[0] == 0
    print("%-15s %-4s %s" % ("projects v2", "--",
                             "available — `dev project` can mirror the board" if has_projects
                             else "not available (optional; needs `gh auth refresh -s project`)"))
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

    ui = sub.add_parser("ui", help="regenerate .dev/ui/<surface>.json + .html and the index")
    ui.add_argument("surface", nargs="?", choices=list(UI_SURFACES))
    ui.add_argument("--milestone", help="the active milestone; its members are the queue")
    ui.add_argument("--open", action="store_true", help="open the result in a browser")
    ui.add_argument("--check", action="store_true", help="report what is stale; write nothing")
    ui.add_argument("--force", action="store_true", help="rebuild every surface, fresh or not")
    ui.add_argument("--serve", action="store_true",
                    help="serve on 127.0.0.1 so board cards can be dragged; Ctrl-C stops")
    ui.add_argument("--port", type=int, default=0, help="port for --serve; default picks a free one")
    ui.set_defaults(func=cmd_ui)

    pj = sub.add_parser("project", help="mirror the computed board into a GitHub Project v2")
    pj.add_argument("--number", type=int, help="project number; omit to list")
    pj.add_argument("--milestone", help="the active milestone; its members are the queue")
    pj.add_argument("--apply", action="store_true", help="actually write; default is a dry run")
    pj.set_defaults(func=cmd_project)

    dr = sub.add_parser("doctor", help="check the environment this family needs")
    dr.set_defaults(func=cmd_doctor)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
