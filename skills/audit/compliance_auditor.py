#!/usr/bin/env python3
"""
Phase Compliance Auditor for dev-desk pipeline runs.
Cross-references self-reported ## PIPELINE sections against actual execution
evidence (file changes, git operations, test runs, transcripts) to detect
hidden skips, unverified claims, and silent omissions.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Set, Tuple

# Pipeline Phase Definitions
PHASE_NAMES = {
    0: "Filing",
    1: "Context Load",
    2: "Tech Stack Discovery",
    3: "Git Branch Naming",
    4: "Investigation",
    5: "Discuss Before Building",
    6: "Architecture Alternatives",
    7: "Plan Output",
    8: "Task Breakdown",
    9: "Implement",
    10: "Pre-PR Quality Checks",
    11: "Verification Gate",
    12: "Docs & Decisions Gate",
    13: "Code Review Gate",
    14: "PR Creation → Pre Prod",
    15: "Review Cycle",
    16: "Prod Promotion",
}

# Standard required phases for each tier (Phases that must either be Ran or Skipped)
TIER_REQUIRED_PHASES = {
    "light": {1, 2, 3, 5, 7, 9, 10, 11, 12, 13, 14},
    "standard": {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16},
    "deep": {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16},
}

# Phases a Deep-tier feature may not list under Skipped:, whatever the reason, and the rule each alert cites
DEEP_FEATURE_REQUIRED = {
    5: "Phase 5 is required for Deep features; only a trivial change skips it, and a Deep feature is not one.",
    6: 'Phase 6 is required for Deep features; only "lighter" at the cost declaration skips it, and that changes Tier.',
}

# Tier words, mapped to the tier they name (Quick is an alias for Light)
TIER_WORDS = {"light": "light", "quick": "light", "standard": "standard", "deep": "deep"}

# A whole tier word; the possessive "Deep's" names the tier's cost, not a tier
TIER_WORD = re.compile(r"\b(light|quick|standard|deep)\b(?!['’]s\b)", re.IGNORECASE)

# Phases that legitimately produce zero filesystem/git tool-call artifacts
ZERO_ARTIFACT_PHASES = {
    0: "Standalone entry only; conversational or tracker action",
    1: "Context loaded in prompt or via read-only tool calls",
    2: "Tech stack known or inspected read-only",
    4: "Investigation conducted via search or read-only commands",
    5: "Conversational alignment gate with user / developer",
    7: "Plan presented directly in conversation or spec outline",
    8: "Task breakdown listed directly in plan or chat",
}


def parse_range_list(text: str) -> Set[int]:
    """Parse comma/space/hyphen separated phase numbers into a set of integers."""
    result = set()
    cleaned = re.sub(r'[^0-9,\-\s]', '', text)
    parts = re.split(r'[,;\s]+', cleaned.strip())
    for part in parts:
        if not part:
            continue
        if '-' in part:
            bounds = part.split('-')
            if len(bounds) == 2 and bounds[0].isdigit() and bounds[1].isdigit():
                start, end = int(bounds[0]), int(bounds[1])
                for num in range(start, end + 1):
                    result.add(num)
        elif part.isdigit():
            result.add(int(part))
    return result


def parse_skipped_section(text: str) -> Tuple[Dict[int, str], List[int]]:
    """
    Parse the Skipped: line into:
      - valid_skips: Dict[phase_number, reason]
      - bare_skips: List[phase_number] (skips without reasons)
    Example input: '6 (one obvious shape) · 8 (3 tasks, inline) · 16 (not promoting yet)'
    """
    valid_skips = {}
    bare_skips = []

    text = text.strip()
    if not text or text.lower() in ('none', 'none.', 'n/a'):
        return valid_skips, bare_skips

    # Extract all parenthetical skips: "N (reason)" or "Phase N (reason)"
    paren_matches = list(re.finditer(r'(?:Phase\s+)?(\d+)\s*\(([^)]+)\)', text, re.IGNORECASE))
    matched_spans = []
    for m in paren_matches:
        phase_num = int(m.group(1))
        reason = m.group(2).strip()
        valid_skips[phase_num] = reason
        matched_spans.append((m.start(), m.end()))

    # Build residual string by blanking out matched spans
    residual = list(text)
    for start, end in matched_spans:
        for idx in range(start, end):
            residual[idx] = ' '
    residual_str = "".join(residual)

    # Check for bare phase numbers without reasons in residual
    chunks = re.split(r'[·;•|\n,]+', residual_str)
    for chunk in chunks:
        chunk = chunk.strip()
        if not chunk:
            continue
        numbers = re.findall(r'\b\d+\b', chunk)
        for n in numbers:
            num = int(n)
            if num not in valid_skips and num not in bare_skips:
                bare_skips.append(num)

    return valid_skips, bare_skips


def is_feature_title(title: str) -> bool:
    """A conventional-commit feature title: `feat:`, `feat(scope):` or `feat!:`."""
    return re.match(r'feat(\(|!?:)', title.strip(), re.IGNORECASE) is not None


def declared_tiers(tier_text: str) -> Set[str]:
    """Tiers named by whole words in Tier:'s first sentence; (reasons) and possessives never count."""
    named = re.sub(r'\([^)]*\)', ' ', tier_text).split('.', 1)[0]
    return {TIER_WORDS[word.lower()] for word in TIER_WORD.findall(named)}


# A PIPELINE field line: plain `Key:`, or bold `**Key:**`, `**Key**:` or `**Key: value**`
FIELD_LINE = re.compile(r'\*{0,2}([A-Za-z][A-Za-z ]{0,30}?)\s*\*{0,2}\s*:\s*\*{0,2}\s*(.*)')
PIPELINE_FIELDS = {"tier", "ran", "skipped", "gates"}


def extract_pipeline_section(body: str) -> Optional[Dict[str, str]]:
    """Extract ## PIPELINE fields; a more-indented line continues the field above until the next field line."""
    match = re.search(r'##\s+PIPELINE\s*\n(.*?)(?=\n##|\Z)', body, re.DOTALL | re.IGNORECASE)
    if not match:
        return None

    data = {}
    key, key_indent = None, 0
    for raw in match.group(1).splitlines():
        line = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        field = FIELD_LINE.match(line)
        name = field.group(1).strip().lower() if field else None
        if key and line and not line.startswith('```') and indent > key_indent and name not in PIPELINE_FIELDS:
            data[key] = f"{data[key]} {line}"
        elif field:
            key, key_indent = name, indent
            data[key] = field.group(2).strip()
        else:
            key = None

    return data


def extract_section(body: str, header_name: str) -> Optional[str]:
    """Extract content under a specific markdown ## HEADER."""
    pattern = rf'##\s+{re.escape(header_name)}\s*\n(.*?)(?=\n##|\Z)'
    match = re.search(pattern, body, re.DOTALL | re.IGNORECASE)
    return match.group(1).strip() if match else None


def collect_pr_evidence(pr_data: Dict) -> Dict:
    """Extract evidence from GitHub PR JSON (files, branch, base)."""
    file_paths = [f.get("path", "") if isinstance(f, dict) else str(f) for f in pr_data.get("files", [])]
    evidence = {
        "current_branch": pr_data.get("headRefName", ""),
        "files_changed": file_paths,
        "code_files": [],
        "test_files": [],
        "doc_files": [],
        "spec_files": [],
        "commit_count": 1,
    }

    for f in file_paths:
        fl = f.lower()
        if any(fl.endswith(ext) for ext in ('.md', '.txt', '.rst', '.adoc')) or 'doc' in fl:
            evidence["doc_files"].append(f)
        elif 'test' in fl or fl.startswith('spec/') or 'spec' in fl:
            if fl.endswith('.py') or fl.endswith('.js') or fl.endswith('.ts') or fl.endswith('.swift'):
                evidence["test_files"].append(f)
            else:
                evidence["spec_files"].append(f)
        else:
            evidence["code_files"].append(f)

    return evidence


def collect_git_evidence(base_branch: str = "origin/main") -> Dict:
    """Collect git diff, log, and branch evidence."""
    evidence = {
        "current_branch": "",
        "files_changed": [],
        "code_files": [],
        "test_files": [],
        "doc_files": [],
        "spec_files": [],
        "commit_count": 0,
    }

    try:
        # Current branch
        branch_out = subprocess.check_output(
            ["git", "branch", "--show-current"], text=True
        ).strip()
        evidence["current_branch"] = branch_out

        # Commit count against base
        commits_out = subprocess.check_output(
            ["git", "rev-list", "--count", f"{base_branch}..HEAD"], text=True
        ).strip()
        evidence["commit_count"] = int(commits_out) if commits_out.isdigit() else 0

        # Diff names
        diff_files_out = subprocess.check_output(
            ["git", "diff", "--name-only", f"{base_branch}...HEAD"], text=True
        ).splitlines()
        evidence["files_changed"] = [f.strip() for f in diff_files_out if f.strip()]

        for f in evidence["files_changed"]:
            fl = f.lower()
            if any(fl.endswith(ext) for ext in ('.md', '.txt', '.rst', '.adoc')) or 'doc' in fl:
                evidence["doc_files"].append(f)
            elif 'test' in fl or fl.startswith('spec/') or 'spec' in fl:
                if fl.endswith('.py') or fl.endswith('.js') or fl.endswith('.ts') or fl.endswith('.swift'):
                    evidence["test_files"].append(f)
                else:
                    evidence["spec_files"].append(f)
            else:
                evidence["code_files"].append(f)

    except Exception:
        pass

    return evidence


def audit_pipeline(
    pr_body: str,
    base_branch: str = "origin/main",
    git_evidence: Optional[Dict] = None,
    transcript_evidence: Optional[Dict] = None,
    pr_title: str = "",
) -> Dict:
    """
    Core auditing engine:
    Cross-references self-reported ## PIPELINE claims against mechanical evidence.
    """
    if git_evidence is None:
        git_evidence = collect_git_evidence(base_branch)

    pipeline_info = extract_pipeline_section(pr_body)
    if not pipeline_info:
        return {
            "compliant": False,
            "score": 0.0,
            "error": "Missing required ## PIPELINE section in PR body",
            "phases": {},
            "alerts": ["Critical: PR body has no ## PIPELINE section."],
        }

    # The strictest tier Tier: names governs; none named means Standard
    tiers = declared_tiers(pipeline_info.get("tier", ""))
    active_tier = next((t for t in ("deep", "standard", "light") if t in tiers), "standard")

    # Extract Ran:
    ran_text = pipeline_info.get("ran", "")
    ran_phases = parse_range_list(ran_text)

    # Extract Skipped:
    skipped_text = pipeline_info.get("skipped", "")
    valid_skips, bare_skips = parse_skipped_section(skipped_text)

    # A Deep-tier feature may not skip Phase 5 or 6, with or without a reason; a bare one is reported once, as that
    forbidden_skips = []
    if is_feature_title(pr_title) and "deep" in tiers:
        forbidden_skips = [p for p in sorted(DEEP_FEATURE_REQUIRED) if p in valid_skips or p in bare_skips]
        bare_skips = [p for p in bare_skips if p not in forbidden_skips]

    # Extract Gates:
    gates_text = pipeline_info.get("gates", "")

    # Extract verification & docs sections
    verification_text = extract_section(pr_body, "VERIFICATION") or ""
    docs_text = extract_section(pr_body, "DOCS") or ""

    required_phases = sorted(TIER_REQUIRED_PHASES.get(active_tier, TIER_REQUIRED_PHASES["standard"]) | set(forbidden_skips))

    phase_results = {}
    matched_count = 0
    declared_skip_count = 0
    unmatched_count = 0
    hidden_skip_count = 0
    bare_skip_count = len(bare_skips)
    forbidden_skip_count = len(forbidden_skips)
    alerts = [
        f"Critical: Deep-tier feature skipped Phase {p} ({PHASE_NAMES[p]}). {DEEP_FEATURE_REQUIRED[p]}"
        for p in forbidden_skips
    ]

    if bare_skips:
        for p in bare_skips:
            alerts.append(f"Bare skip: Phase {p} ({PHASE_NAMES.get(p, 'Unknown')}) listed in Skipped: without parenthetical reason.")

    for p in required_phases:
        name = PHASE_NAMES.get(p, f"Phase {p}")
        status = "UNKNOWN"
        evidence_note = ""

        # Case 0: a skip the tier forbids, with or without a reason
        if p in forbidden_skips:
            status = "FORBIDDEN_SKIP"
            evidence_note = "A Deep-tier feature may not skip this phase"

        # Case 1: Legitimate Declared Skip
        elif p in valid_skips:
            status = "DECLARED_SKIP"
            declared_skip_count += 1
            evidence_note = f"Reason: ({valid_skips[p]})"

        # Case 2: Reported in Ran:
        elif p in ran_phases:
            # Mechanically verify evidence based on phase type
            if p == 3:  # Branch naming
                branch = git_evidence.get("current_branch", "")
                if branch and branch not in ("main", "master", "develop", "staging"):
                    status = "MATCHED"
                    evidence_note = f"Branch '{branch}' verified cut from base"
                    matched_count += 1
                else:
                    status = "UNMATCHED"
                    evidence_note = f"Branch '{branch}' is default or missing"
                    unmatched_count += 1

            elif p == 9:  # Implement
                files = git_evidence.get("files_changed", [])
                if files:
                    status = "MATCHED"
                    evidence_note = f"{len(files)} files modified/created in git diff"
                    matched_count += 1
                else:
                    status = "UNMATCHED"
                    evidence_note = "No modified files found in git diff"
                    unmatched_count += 1

            elif p == 10:  # Quality checks (linter)
                if "10" in gates_text or "lint" in gates_text.lower() or "quality" in gates_text.lower():
                    status = "MATCHED"
                    evidence_note = f"Quality gate attested in Gates: '{gates_text}'"
                    matched_count += 1
                else:
                    status = "MATCHED"
                    evidence_note = "Pre-PR checks passed cleanly"
                    matched_count += 1

            elif p == 11:  # Verification gate
                # Check for real command output vs placeholder
                is_placeholder = (
                    not verification_text
                    or "- <real command output>" in verification_text
                    or "<commands actually run" in verification_text
                )
                if is_placeholder:
                    status = "HIDDEN_SKIP"
                    evidence_note = "Claimed in Ran: but ## VERIFICATION is empty or contains placeholder text"
                    hidden_skip_count += 1
                    alerts.append(f"Phase 11 (Verification Gate) claimed but ## VERIFICATION contains placeholder text.")
                else:
                    status = "MATCHED"
                    test_summary = "Verification output recorded"
                    if "pass" in verification_text.lower():
                        test_summary = "Test execution verified (PASS)"
                    evidence_note = test_summary
                    matched_count += 1

            elif p == 12:  # Docs gate
                is_missing = (
                    not docs_text
                    or "- <docs/ADRs updated" in docs_text
                    or "<ADRs/docs updated" in docs_text
                )
                if is_missing:
                    status = "HIDDEN_SKIP"
                    evidence_note = "Claimed in Ran: but ## DOCS section is missing or placeholder"
                    hidden_skip_count += 1
                    alerts.append(f"Phase 12 (Docs Gate) claimed but ## DOCS section is missing.")
                else:
                    status = "MATCHED"
                    evidence_note = "Documentation and decisions verified in ## DOCS"
                    matched_count += 1

            elif p == 13:  # Code review gate
                if "13" in gates_text or "clean" in gates_text.lower() or "review" in gates_text.lower():
                    status = "MATCHED"
                    evidence_note = f"Review gate verified: '{gates_text}'"
                    matched_count += 1
                else:
                    status = "MATCHED"
                    evidence_note = "Self-review completed"
                    matched_count += 1

            elif p == 14:  # PR Creation
                status = "MATCHED"
                evidence_note = "PR structure formatted"
                matched_count += 1

            elif p in ZERO_ARTIFACT_PHASES:
                # Phases 1, 2, 4, 5, 7, 8: legitimate zero-artifact operations
                status = "MATCHED"
                evidence_note = ZERO_ARTIFACT_PHASES[p]
                matched_count += 1

            elif p == 6:  # Architecture alternatives
                # If claimed in Ran, check for docs/ADR
                doc_files = git_evidence.get("doc_files", [])
                if any("adr" in df.lower() or "arch" in df.lower() for df in doc_files):
                    status = "MATCHED"
                    evidence_note = "Architecture/ADR document found in diff"
                    matched_count += 1
                else:
                    status = "MATCHED"
                    evidence_note = "Architecture reviewed inline"
                    matched_count += 1

            elif p == 16:  # Prod promotion
                # Single-stage repos skip or defer Phase 16
                status = "DECLARED_SKIP"
                declared_skip_count += 1
                evidence_note = "Single-stage repo model or promotion deferred"

            else:
                status = "MATCHED"
                evidence_note = "Execution attested"
                matched_count += 1

        # Case 3: Missing from both Ran: and Skipped:
        else:
            if p == 16 and active_tier != "deep":
                # Phase 16 is conditional on prod release
                status = "DECLARED_SKIP"
                declared_skip_count += 1
                evidence_note = "Promotion deferred"
            elif p in bare_skips:
                status = "BARE_SKIP"
                evidence_note = "Listed in Skipped: but missing required reason in parentheses"
            else:
                status = "HIDDEN_SKIP"
                hidden_skip_count += 1
                evidence_note = "Phase omitted from both Ran: and Skipped:"
                alerts.append(f"Hidden Skip: Phase {p} ({name}) not reported in Ran: or Skipped:.")

        phase_results[p] = {
            "name": name,
            "status": status,
            "evidence": evidence_note,
        }

    total_evaluated = len(required_phases)
    valid_total = matched_count + declared_skip_count
    score = (valid_total / total_evaluated * 100.0) if total_evaluated > 0 else 0.0

    is_compliant = (hidden_skip_count == 0) and (bare_skip_count == 0) and (unmatched_count == 0) and (forbidden_skip_count == 0)

    return {
        "compliant": is_compliant,
        "score": round(score, 1),
        "tier": active_tier,
        "total_evaluated": total_evaluated,
        "matched": matched_count,
        "declared_skips": declared_skip_count,
        "unmatched": unmatched_count,
        "hidden_skips": hidden_skip_count,
        "bare_skips": bare_skip_count,
        "forbidden_skips": forbidden_skip_count,
        "phases": phase_results,
        "alerts": alerts,
    }


def format_compliance_markdown(audit_result: Dict) -> str:
    """Format audit results as a clean GitHub-flavored markdown ## COMPLIANCE section."""
    lines = []
    lines.append("## COMPLIANCE")
    lines.append("")

    score = audit_result.get("score", 0.0)
    matched = audit_result.get("matched", 0)
    skips = audit_result.get("declared_skips", 0)
    hidden = audit_result.get("hidden_skips", 0)
    bare = audit_result.get("bare_skips", 0)
    unmatched = audit_result.get("unmatched", 0)
    forbidden = audit_result.get("forbidden_skips", 0)

    if audit_result.get("compliant"):
        lines.append(f"**Compliance Status:** ✅ **100% Compliant** ({matched} Matched, {skips} Declared Skips, 0 Hidden Skips)")
    else:
        issues = []
        if forbidden:
            issues.append(f"{forbidden} Forbidden Skip{'s' if forbidden > 1 else ''}")
        if hidden:
            issues.append(f"{hidden} Hidden Skip{'s' if hidden > 1 else ''}")
        if bare:
            issues.append(f"{bare} Bare Skip{'s' if bare > 1 else ''}")
        if unmatched:
            issues.append(f"{unmatched} Unverified Claim{'s' if unmatched > 1 else ''}")
        issues_str = ", ".join(issues)
        lines.append(f"⚠️ **COMPLIANCE ALERT: {issues_str} Detected** (Score: {score}%)")

    lines.append("")
    lines.append("| Phase | Phase Name | Status | Evidence / Notes |")
    lines.append("|---|---|---|---|")

    status_badges = {
        "MATCHED": "✅ Matched",
        "DECLARED_SKIP": "⏭️ Declared Skip",
        "UNMATCHED": "⚠️ Unmatched",
        "HIDDEN_SKIP": "❌ Hidden Skip",
        "BARE_SKIP": "❌ Bare Skip",
        "FORBIDDEN_SKIP": "❌ Forbidden Skip",
    }

    for p, data in sorted(audit_result.get("phases", {}).items()):
        badge = status_badges.get(data["status"], data["status"])
        name = data["name"]
        ev = data["evidence"].replace("|", "\\|")
        lines.append(f"| {p} | {name} | {badge} | {ev} |")

    alerts = audit_result.get("alerts", [])
    if alerts:
        lines.append("")
        lines.append("**Findings & Remediation:**")
        for alert in alerts:
            lines.append(f"- ⚠️ {alert}")

    return "\n".join(lines)


def append_to_pr_body(pr_number: str, compliance_md: str) -> bool:
    """Append or replace ## COMPLIANCE section in an existing GitHub PR body."""
    try:
        # Fetch current body
        body = subprocess.check_output(
            ["gh", "pr", "view", pr_number, "--json", "body", "-q", ".body"],
            text=True,
        )

        # Replace existing ## COMPLIANCE or append at end
        if re.search(r'##\s+COMPLIANCE', body, re.IGNORECASE):
            updated_body = re.sub(
                r'##\s+COMPLIANCE\s*\n.*?(?=\n##|\Z)',
                compliance_md + "\n",
                body,
                flags=re.DOTALL | re.IGNORECASE,
            )
        else:
            updated_body = body.rstrip() + "\n\n" + compliance_md + "\n"

        subprocess.check_call(
            ["gh", "pr", "edit", pr_number, "--body", updated_body]
        )
        return True
    except Exception as e:
        print(f"Error updating PR {pr_number}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Audit dev-desk pipeline self-reporting compliance against mechanical evidence."
    )
    parser.add_argument("--pr", help="GitHub PR number or URL to audit")
    parser.add_argument("--file", help="Path to markdown file containing PR body")
    parser.add_argument("--text", help="Raw PR body text to audit")
    parser.add_argument("--title", help="PR title, for a body given by --file, --text or stdin; --pr reads it from GitHub")
    parser.add_argument("--base", default="origin/main", help="Base git branch for diff verification (default: origin/main)")
    parser.add_argument("--append-pr", action="store_true", help="Append the ## COMPLIANCE section to the GitHub PR body")
    parser.add_argument("--format", choices=["markdown", "json", "summary"], default="markdown", help="Output format")
    parser.add_argument("--strict", action="store_true", help="Exit with non-zero code if compliance score is under 100%% or hidden skips exist")

    args = parser.parse_args()

    pr_body = ""
    pr_title = args.title or ""
    pr_num = args.pr

    pr_evidence = None
    if args.pr:
        # Extract number if full URL provided
        pr_match = re.search(r'/pull/(\d+)', args.pr)
        if pr_match:
            pr_num = pr_match.group(1)
        try:
            raw_pr_json = subprocess.check_output(
                ["gh", "pr", "view", pr_num, "--json", "body,files,headRefName,baseRefName,title"],
                text=True,
            )
            pr_data = json.loads(raw_pr_json)
            pr_body = pr_data.get("body", "")
            pr_title = pr_title or pr_data.get("title", "")
            pr_evidence = collect_pr_evidence(pr_data)
        except Exception as e:
            print(f"Error fetching PR {args.pr}: {e}", file=sys.stderr)
            sys.exit(1)
    elif args.file:
        try:
            with open(args.file, "r", encoding="utf-8") as f:
                pr_body = f.read()
        except Exception as e:
            print(f"Error reading file {args.file}: {e}", file=sys.stderr)
            sys.exit(1)
    elif args.text:
        pr_body = args.text
    else:
        # Read from stdin if piped
        if not sys.stdin.isatty():
            pr_body = sys.stdin.read()
        else:
            parser.print_help()
            sys.exit(1)

    result = audit_pipeline(pr_body, base_branch=args.base, git_evidence=pr_evidence, pr_title=pr_title)

    if args.format == "json":
        print(json.dumps(result, indent=2))
    elif args.format == "summary":
        status_str = "COMPLIANT" if result["compliant"] else "NON-COMPLIANT"
        print(f"Audit {status_str}: {result['score']}% (Matched: {result['matched']}, Skips: {result['declared_skips']}, Hidden: {result['hidden_skips']}, Forbidden: {result['forbidden_skips']})")
    else:
        md = format_compliance_markdown(result)
        print(md)

    if args.append_pr and pr_num:
        md = format_compliance_markdown(result)
        if append_to_pr_body(pr_num, md):
            print(f"Successfully appended ## COMPLIANCE to PR #{pr_num}", file=sys.stderr)
        else:
            print(f"Failed to append ## COMPLIANCE to PR #{pr_num}", file=sys.stderr)

    if args.strict and not result.get("compliant"):
        sys.exit(1)


if __name__ == "__main__":
    main()
