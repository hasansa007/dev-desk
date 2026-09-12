#!/usr/bin/env python3
"""
Automated Test Harness for dev-skill Phase Compliance Auditor.
Validates:
1. Honest Pipeline Run: 100% compliance score, matched phases, valid declared skips.
2. Hidden Skip Detection (Placeholder Verification): Claimed Phase 11 without test output.
3. Hidden Skip Detection (Omission): Required phase missing from both Ran: and Skipped:.
4. Bare Skip Detection: Phase in Skipped: without explanatory reason.
5. Zero-Artifact Phase Handling: False positive prevention for conversational/in-memory phases.
6. PR ## COMPLIANCE Markdown Generation: Valid structure, badges, alert formatting.
7. Real-world Trace Audit: Cross-referencing real git PR diff and evidence.
8. Deep-Feature Gate: a feat PR on the Deep tier may not skip Phase 5 or 6, whatever the reason; reported once.
9. PIPELINE Parsing: wrapped continuation lines, bold **Key:** fields, and the strictest whole tier word.
"""

import os
import sys
import unittest

# The auditor lives beside the dev:audit door, in skills/audit/ (ADR 0015)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, os.path.join(REPO_ROOT, "skills", "audit"))

from compliance_auditor import (
    audit_pipeline,
    extract_pipeline_section,
    format_compliance_markdown,
    parse_range_list,
    parse_skipped_section,
)

PHASE_6_ALERT = ('Critical: Deep-tier feature skipped Phase 6 (Architecture Alternatives). Phase 6 is required '
                 'for Deep features; only "lighter" at the cost declaration skips it, and that changes Tier.')
PHASE_5_ALERT = ('Critical: Deep-tier feature skipped Phase 5 (Discuss Before Building). Phase 5 is required '
                 'for Deep features; only a trivial change skips it, and a Deep feature is not one.')


def deep_gate_body(tier: str, ran: str, skipped: str) -> str:
    """A synthetic PR body that passes every other check, so only the Deep-feature gate can alert."""
    return f"""
## SUMMARY
Synthetic body for the Deep-feature gate.

## PIPELINE
Tier:    {tier}
Ran:     {ran}
Skipped: {skipped}
Gates:   10 clean · 12 docs updated · 13 clean

## VERIFICATION
- unittest: 9 passed

## DOCS
- README.md updated
"""


def gate_alerts(result: dict) -> list:
    """The alerts raised by the Deep-feature gate, and no others."""
    return [a for a in result["alerts"] if "Deep-tier feature skipped" in a]


class TestComplianceAuditor(unittest.TestCase):

    def setUp(self):
        self.mock_git_evidence = {
            "current_branch": "feature/test-phase-auditor",
            "files_changed": ["src/main.py", "tests/test_main.py", "README.md"],
            "code_files": ["src/main.py"],
            "test_files": ["tests/test_main.py"],
            "doc_files": ["README.md"],
            "spec_files": [],
            "commit_count": 2,
        }

    def test_01_honest_standard_run(self):
        """Test an honest run where all phases are either run with evidence or declared with reason."""
        pr_body = """
## SUMMARY
Implemented compliance auditor feature.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9-14
Skipped: 6 (single design shape) · 8 (subtasks inline) · 16 (single-stage model)
Gates:   10 clean · 12 docs updated (README.md) · 13 clean (self-review passed)

## VERIFICATION
- pytest: 18 passed in 0.42s
- lint: ruff check clean (0 errors)

## DOCS
- README.md updated with new command reference

## HOW TO TEST
Setup: python3 -m pytest
"""
        result = audit_pipeline(pr_body, git_evidence=self.mock_git_evidence)
        self.assertTrue(result["compliant"], "Honest run should be marked compliant")
        self.assertEqual(result["score"], 100.0, "Honest run should score 100%")
        self.assertEqual(result["hidden_skips"], 0, "Honest run should have 0 hidden skips")
        self.assertEqual(result["bare_skips"], 0, "Honest run should have 0 bare skips")
        self.assertEqual(result["declared_skips"], 3, "Phases 6, 8, 16 should be declared skips")

        # Check phase statuses
        self.assertEqual(result["phases"][1]["status"], "MATCHED")
        self.assertEqual(result["phases"][6]["status"], "DECLARED_SKIP")
        self.assertEqual(result["phases"][9]["status"], "MATCHED")
        self.assertEqual(result["phases"][11]["status"], "MATCHED")
        self.assertEqual(result["phases"][12]["status"], "MATCHED")
        self.assertEqual(result["phases"][16]["status"], "DECLARED_SKIP")
        print("✓ Test 1 Passed: Honest run verified with 100% compliance")

    def test_02_hidden_skip_placeholder_verification(self):
        """Test detection when Phase 11 is claimed in Ran: but ## VERIFICATION has template placeholder."""
        pr_body = """
## SUMMARY
Built feature without real verification.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9-14
Skipped: 6 (one design shape) · 8 (subtasks inline) · 16 (deferred)
Gates:   10 clean · 12 clean · 13 clean

## VERIFICATION
- <real command output>

## DOCS
- README.md updated

## HOW TO TEST
Run tests
"""
        result = audit_pipeline(pr_body, git_evidence=self.mock_git_evidence)
        self.assertFalse(result["compliant"], "Placeholder verification must NOT be compliant")
        self.assertGreaterEqual(result["hidden_skips"], 1, "Must detect hidden skip on Phase 11")
        self.assertEqual(result["phases"][11]["status"], "HIDDEN_SKIP")
        self.assertIn("placeholder", result["phases"][11]["evidence"].lower())
        print("✓ Test 2 Passed: Hidden skip detected on placeholder ## VERIFICATION")

    def test_03_hidden_skip_unreported_omission(self):
        """Test detection when a required phase (Phase 10) is omitted from both Ran: and Skipped:."""
        pr_body = """
## SUMMARY
Omitted phase 10 entirely.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9, 11-14
Skipped: 6 (one shape) · 8 (inline) · 16 (deferred)
Gates:   12 docs updated · 13 clean

## VERIFICATION
- pytest: 12 passed

## DOCS
- README.md updated
"""
        result = audit_pipeline(pr_body, git_evidence=self.mock_git_evidence)
        self.assertFalse(result["compliant"], "Omission must NOT be compliant")
        self.assertIn(10, result["phases"])
        self.assertEqual(result["phases"][10]["status"], "HIDDEN_SKIP")
        self.assertIn("Hidden Skip: Phase 10", " ".join(result["alerts"]))
        print("✓ Test 3 Passed: Hidden skip detected when Phase 10 omitted from Ran: and Skipped:")

    def test_04_bare_skip_detection(self):
        """Test detection when a skipped phase lacks explanatory parentheses."""
        pr_body = """
## SUMMARY
Bare skip in pipeline.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9-14
Skipped: 6, 8 (subtasks inline) · 16 (deferred)
Gates:   10 clean · 12 docs updated · 13 clean

## VERIFICATION
- pytest: 10 passed

## DOCS
- README.md updated
"""
        result = audit_pipeline(pr_body, git_evidence=self.mock_git_evidence)
        self.assertFalse(result["compliant"], "Bare skip violates pipeline rules")
        self.assertEqual(result["phases"][6]["status"], "BARE_SKIP")
        self.assertIn(6, [int(p) for p in result["phases"] if result["phases"][p]["status"] == "BARE_SKIP"])
        print("✓ Test 4 Passed: Bare skip detected on Phase 6 (missing parentheses reason)")

    def test_05_zero_artifact_false_positive_prevention(self):
        """Test that conversational and in-memory phases (1, 2, 4, 5, 7, 8) do NOT generate false positives."""
        # Git diff containing code changes but no transcript
        evidence_no_transcript = {
            "current_branch": "feature/refactor",
            "files_changed": ["src/service.py"],
            "code_files": ["src/service.py"],
            "test_files": [],
            "doc_files": [],
            "spec_files": [],
            "commit_count": 1,
        }
        pr_body = """
## SUMMARY
Refactored internal logic.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9-14
Skipped: 6 (straightforward refactor) · 8 (single task) · 16 (deferred)
Gates:   10 clean · 12 none needed — checked: refactor only · 13 clean

## VERIFICATION
- Automated build & smoke test clean: PASS

## DOCS
- none needed — checked: internal refactor only

## HOW TO TEST
Run tests
"""
        result = audit_pipeline(pr_body, git_evidence=evidence_no_transcript)
        # Verify Phase 5 (Discuss Before Building) is treated as MATCHED conversational gate
        self.assertEqual(result["phases"][5]["status"], "MATCHED")
        # Verify Phase 1 (Context load) is treated as MATCHED
        self.assertEqual(result["phases"][1]["status"], "MATCHED")
        # Verify Phase 2 (Tech stack) is treated as MATCHED
        self.assertEqual(result["phases"][2]["status"], "MATCHED")
        # Verify Phase 4 (Investigation) is treated as MATCHED
        self.assertEqual(result["phases"][4]["status"], "MATCHED")
        # Verify Phase 7 (Plan) is treated as MATCHED
        self.assertEqual(result["phases"][7]["status"], "MATCHED")
        # Ensure zero false positives occurred on these zero-artifact phases
        zero_artifact_phases = [1, 2, 4, 5, 7]
        for p in zero_artifact_phases:
            self.assertEqual(result["phases"][p]["status"], "MATCHED", f"Phase {p} should be MATCHED")
        print("✓ Test 5 Passed: Zero-artifact phases correctly handled (0 false positives)")

    def test_06_compliance_markdown_formatting(self):
        """Test formatting of ## COMPLIANCE markdown block."""
        pr_body = """
## SUMMARY
Formatting test.

## PIPELINE
Tier: Standard
Ran: 1-5, 7, 9-14
Skipped: 6 (one shape) · 8 (inline) · 16 (single-stage)
Gates: 10 clean · 12 docs updated · 13 clean

## VERIFICATION
- python3 test.py: PASS

## DOCS
- README.md updated
"""
        result = audit_pipeline(pr_body, git_evidence=self.mock_git_evidence)
        md = format_compliance_markdown(result)
        self.assertIn("## COMPLIANCE", md)
        self.assertIn("✅ **100% Compliant**", md)
        self.assertIn("| Phase | Phase Name | Status | Evidence / Notes |", md)
        self.assertIn("✅ Matched", md)
        self.assertIn("⏭️ Declared Skip", md)
        print("✓ Test 6 Passed: ## COMPLIANCE markdown block formatted cleanly")

    def test_07_real_world_pr_detection(self):
        """Test against real-world PR #47 body pattern to verify detection of omitted Phase 10."""
        pr_47_body = """
## SUMMARY
- Implements the `/dev:rollback` door in `dev-skill`.

## PIPELINE
Tier:    Standard
Ran:     1-5, 7, 9, 11-14
Skipped: 6 (single design shape) · 8 (subtasks inline) · 16 (single-stage model; prod secrets pre-flight passed at Phase 14)
Gates:   10 clean · 12 docs updated (README, COMMANDS, WORKFLOW) · 13 clean (all tests pass, 0 lints)

## VERIFICATION
- Line budget check: shared/pipeline.md exactly 995 lines (PASS).
- Test suite: python3 test-projects/rollback/test_rollback_engine.py (5/5 tests passing).

## DOCS
- README.md: Added /dev:rollback to doors table.

## HOW TO TEST
python3 test-projects/rollback/test_rollback_engine.py
"""
        result = audit_pipeline(pr_47_body, git_evidence=self.mock_git_evidence)
        # PR 47 accidentally omitted Phase 10 from Ran: (it wrote '9, 11-14')
        self.assertEqual(result["phases"][10]["status"], "HIDDEN_SKIP")
        self.assertFalse(result["compliant"])
        # Phase 16 parenthetical containing semicolon must NOT trigger bare skip
        self.assertEqual(result["phases"][16]["status"], "DECLARED_SKIP")
        self.assertEqual(result["bare_skips"], 0)
        print("✓ Test 7 Passed: Accurately caught PR #47 omission of Phase 10 while handling semicolon reasons")

    def test_08_deep_feature_skipping_phase_6_is_critical(self):
        """A feat PR on the Deep tier that skips Phase 6 gets a Critical alert, whatever the reason."""
        body = deep_gate_body("Deep", "1-5, 7-14", "6 (scope questions already answered) · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add an offline sync engine")
        self.assertEqual(gate_alerts(result), [PHASE_6_ALERT])
        self.assertEqual(result["phases"][6]["status"], "FORBIDDEN_SKIP")
        self.assertEqual(result["forbidden_skips"], 1)
        self.assertFalse(result["compliant"], "A reason does not make a Deep feature's Phase 6 skip legitimate")
        self.assertIn("COMPLIANCE ALERT: 1 Forbidden Skip Detected", format_compliance_markdown(result))
        print("✓ Test 8 Passed: Deep-tier feat skipping Phase 6 raises a Critical alert")

    def test_09_deep_feature_skipping_phase_5_is_critical(self):
        """A feat(scope) PR on the Deep tier that skips Phase 5 gets a Critical alert."""
        body = deep_gate_body("Deep", "1-4, 6-14", "5 (developer asked to go fast) · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat(sync): add an offline sync engine")
        self.assertEqual(gate_alerts(result), [PHASE_5_ALERT])
        self.assertEqual(result["phases"][5]["status"], "FORBIDDEN_SKIP")
        self.assertFalse(result["compliant"])
        print("✓ Test 9 Passed: Deep-tier feat(scope) skipping Phase 5 raises a Critical alert")

    def test_10_deep_fix_skipping_phase_6_keeps_todays_behaviour(self):
        """A fix PR on the Deep tier may still declare a Phase 6 skip."""
        body = deep_gate_body("Deep", "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="fix: reject expired session tokens")
        self.assertEqual(result["alerts"], [])
        self.assertEqual(result["phases"][6]["status"], "DECLARED_SKIP")
        self.assertEqual(result["forbidden_skips"], 0)
        self.assertTrue(result["compliant"])
        print("✓ Test 10 Passed: Deep-tier fix may still declare a Phase 6 skip")

    def test_11_standard_feature_skipping_phase_6_keeps_todays_behaviour(self):
        """A feat PR on the Standard tier may still declare a Phase 6 skip."""
        body = deep_gate_body("Standard", "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add a copy-link button")
        self.assertEqual(result["alerts"], [])
        self.assertEqual(result["phases"][6]["status"], "DECLARED_SKIP")
        self.assertEqual(result["forbidden_skips"], 0)
        self.assertTrue(result["compliant"])
        print("✓ Test 11 Passed: Standard-tier feat may still declare a Phase 6 skip")

    def test_12_deep_feature_running_phase_6_is_clean(self):
        """A feat PR on the Deep tier that ran Phase 6 raises nothing."""
        body = deep_gate_body("Deep", "1-14", "16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add an offline sync engine")
        self.assertEqual(result["alerts"], [])
        self.assertEqual(result["phases"][6]["status"], "MATCHED")
        self.assertTrue(result["compliant"])
        print("✓ Test 12 Passed: Deep-tier feat that ran Phase 6 raises nothing")

    def test_13_mixed_tier_naming_deep_counts_as_deep(self):
        """A feat PR whose Tier: names Deep in any ·-separated part is held to the Deep rule."""
        body = deep_gate_body("Standard (moves) · Deep (auth flow)", "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add passkey sign-in")
        self.assertEqual(gate_alerts(result), [PHASE_6_ALERT])
        self.assertFalse(result["compliant"])
        print("✓ Test 13 Passed: a mixed Tier: line that names Deep is held to the Deep rule")

    def test_14_deep_in_a_reason_or_prose_is_not_a_tier(self):
        """Deep named inside a (reason) or trailing prose is not a tier, so a "lighter" answer stays Standard."""
        for tier in ('Standard (answered "lighter" to Deep\'s cost declaration)',
                     '**Standard**. Deep was offered; the developer said lighter.'):
            with self.subTest(tier=tier):
                body = deep_gate_body(tier, "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
                result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add a copy-link button")
                self.assertEqual(gate_alerts(result), [])
        print("✓ Test 14 Passed: Deep inside a reason or prose is not read as the tier")

    def test_15_wrapped_continuation_lines_join_their_key(self):
        """An indented line continues the Ran:, Skipped: or Gates: value above it, inside a code fence."""
        body = """
## PIPELINE

```
Tier:    Deep
Ran:     1, 2, 3, 4, 5, 6, 7,
         8, 9, 10, 11, 12, 13, 14
Skipped: 0 (no issue) · 15 (no human review
         requested) · 16 (single-stage repo: …)
Gates:   10 clean · 12 docs updated
         · 13 clean
```

## VERIFICATION
- unittest: 9 passed

## DOCS
- README.md updated
"""
        fields = extract_pipeline_section(body)
        valid_skips, bare_skips = parse_skipped_section(fields["skipped"])
        self.assertEqual(valid_skips[16], "single-stage repo: …")
        self.assertEqual(valid_skips[15], "no human review requested")
        self.assertEqual(bare_skips, [])
        self.assertIn("13 clean", fields["gates"])
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence)
        self.assertEqual(result["phases"][16]["status"], "DECLARED_SKIP")
        self.assertEqual(result["hidden_skips"], 0)
        self.assertEqual(result["alerts"], [])
        self.assertTrue(result["compliant"])
        print("✓ Test 15 Passed: wrapped Ran:, Skipped: and Gates: lines join the field above")

    def test_16_bold_keys_read_like_plain_keys(self):
        """**Tier: …**, **Ran:** and **Skipped:** are read exactly as their plain forms are."""
        bold = """
## PIPELINE

**Tier: Deep.** Synthetic prose after the tier.

**Ran:** 1 · 2 · 3 · 4 · 5 · 7 · 8 · 9 · 10 · 11 · 12 · 13 · 14

**Skipped:** 6 (one obvious shape) · 16 (not promoting yet)

**Gates:** 10 clean · 12 docs updated · 13 clean

## VERIFICATION
- unittest: 9 passed

## DOCS
- README.md updated
"""
        plain = deep_gate_body("Deep", "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
        title = "feat: add an offline sync engine"
        bold_result = audit_pipeline(bold, git_evidence=self.mock_git_evidence, pr_title=title)
        plain_result = audit_pipeline(plain, git_evidence=self.mock_git_evidence, pr_title=title)
        self.assertEqual(bold_result["tier"], "deep")
        self.assertEqual(bold_result["hidden_skips"], 0)
        self.assertEqual(gate_alerts(bold_result), [PHASE_6_ALERT])
        self.assertEqual(bold_result["alerts"], plain_result["alerts"])
        self.assertEqual({p: v["status"] for p, v in bold_result["phases"].items()},
                         {p: v["status"] for p, v in plain_result["phases"].items()})
        print("✓ Test 16 Passed: bold **Key:** fields are read like plain ones")

    def test_17_tier_is_the_strictest_whole_tier_word(self):
        """The strictest whole tier word outside (reasons), before the first '.', governs; "Deep's" is not a tier."""
        cases = [
            ('Standard (answered "lighter" to Deep\'s cost)', "standard"),
            ("Standard — lighter than Deep's cost", "standard"),
            ("Standard, escalated to Deep in practice", "deep"),
            ("**Light**. One file, prose only.", "light"),
            ("Quick (docs)", "light"),
            ("standard — Deep checks on the auth path only", "deep"),
            ("Deep (security fix) · Quick (docs)", "deep"),
            ("Light (docs) · Deep (auth flow)", "deep"),
        ]
        for tier, expected in cases:
            with self.subTest(tier=tier):
                body = deep_gate_body(tier, "1-5, 7-14", "6 (one obvious shape) · 16 (not promoting yet)")
                self.assertEqual(audit_pipeline(body, git_evidence=self.mock_git_evidence)["tier"], expected)
        print("✓ Test 17 Passed: the strictest whole tier word governs, and Deep's is not a tier")

    def test_18_escalated_to_deep_cannot_escape_the_gate(self):
        """A bold Tier: that opens with Standard but escalates to Deep is held to the Deep rule."""
        body = """
## PIPELINE

**Tier: Standard, escalated to Deep in practice.** Synthetic prose after the tier.

**Ran:** 1 · 2 · 3 · 4 · 5 · 7 · 8 · 9 · 10 · 11 · 12 · 13 · 14

**Skipped:** 6 (one obvious shape) · 16 (not promoting yet)

## VERIFICATION
- unittest: 9 passed

## DOCS
- README.md updated
"""
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add an offline sync engine")
        self.assertEqual(result["tier"], "deep")
        self.assertEqual(gate_alerts(result), [PHASE_6_ALERT])
        self.assertFalse(result["compliant"])
        print("✓ Test 18 Passed: a Tier: escalated to Deep cannot escape the gate")

    def test_19_a_forbidden_bare_skip_is_reported_once(self):
        """A bare Phase 5 skip on a Deep feature raises only the Critical; other bare skips still alert."""
        body = deep_gate_body("Deep", "1-4, 6, 7, 9-14", "5 · 8 · 16 (not promoting yet)")
        result = audit_pipeline(body, git_evidence=self.mock_git_evidence, pr_title="feat: add an offline sync engine")
        self.assertEqual(result["alerts"], [
            PHASE_5_ALERT,
            "Bare skip: Phase 8 (Task Breakdown) listed in Skipped: without parenthetical reason.",
        ])
        self.assertEqual(result["phases"][5]["status"], "FORBIDDEN_SKIP")
        self.assertEqual(result["phases"][8]["status"], "BARE_SKIP")
        self.assertEqual(result["bare_skips"], 1)
        self.assertIn("COMPLIANCE ALERT: 1 Forbidden Skip, 1 Bare Skip Detected", format_compliance_markdown(result))
        print("✓ Test 19 Passed: a forbidden bare skip is reported once, as the Critical")


if __name__ == "__main__":
    print("=" * 64)
    print("Running Phase Compliance Auditor Test Suite")
    print("=" * 64)
    suite = unittest.TestLoader().loadTestsFromTestCase(TestComplianceAuditor)
    runner = unittest.TextTestRunner(verbosity=0)
    test_result = runner.run(suite)
    if test_result.wasSuccessful():
        print("=" * 64)
        print(f"ALL {test_result.testsRun}/{test_result.testsRun} TESTS PASSED!")
        print("=" * 64)
        sys.exit(0)
    else:
        print("=" * 64)
        print(f"TESTS FAILED: {len(test_result.failures)} failures, {len(test_result.errors)} errors")
        print("=" * 64)
        sys.exit(1)
