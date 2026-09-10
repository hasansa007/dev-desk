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
"""

import os
import sys
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.compliance_auditor import (
    audit_pipeline,
    format_compliance_markdown,
    parse_range_list,
    parse_skipped_section,
)


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
