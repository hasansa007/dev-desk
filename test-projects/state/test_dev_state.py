#!/usr/bin/env python3
"""Tests for scripts/dev.py — run with: PYTHONPATH=. python3 test-projects/state/test_dev_state.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.dev import (  # noqa: E402
    main,
    phase_group,
    slugify,
    state_path,
)


def git(args, cwd):
    subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, check=False)


class TempRepo:
    """A throwaway git repo with one commit, so HEAD and branch resolve like a real one."""

    def __enter__(self):
        self.dir = tempfile.mkdtemp()
        self.prev = os.getcwd()
        git(["init", "-q", "-b", "main"], self.dir)
        git(["config", "user.email", "t@example.com"], self.dir)
        git(["config", "user.name", "t"], self.dir)
        with open(os.path.join(self.dir, "f.txt"), "w") as fh:
            fh.write("x\n")
        git(["add", "-A"], self.dir)
        git(["commit", "-qm", "init"], self.dir)
        os.chdir(self.dir)
        return self

    def __exit__(self, *exc):
        os.chdir(self.prev)
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)


class SlugTests(unittest.TestCase):
    def test_slash_in_branch_never_creates_a_subdirectory(self):
        self.assertEqual(slugify("feature/tracker-and-pipeline-state"),
                         "feature-tracker-and-pipeline-state")
        self.assertNotIn("/", slugify("gh-42/some/deep/name"))

    def test_state_path_stays_one_level_under_dot_dev(self):
        p = state_path("/repo", "release/1.0")
        self.assertEqual(os.path.dirname(p), os.path.join("/repo", ".dev"))

    def test_dots_and_dashes_survive_slugging(self):
        self.assertEqual(slugify("v1.2.3-rc"), "v1.2.3-rc")


class PhaseGroupTests(unittest.TestCase):
    def test_boundaries_match_the_documented_axis(self):
        self.assertEqual(phase_group(1), "planning")
        self.assertEqual(phase_group(8), "planning")
        self.assertEqual(phase_group(9), "coding")
        self.assertEqual(phase_group(10), "coding")
        self.assertEqual(phase_group(11), "validation")
        self.assertEqual(phase_group(13), "validation")
        self.assertEqual(phase_group(14), "review")


class CheckpointTests(unittest.TestCase):
    def test_checkpoint_writes_state_a_reader_can_load(self):
        with TempRepo() as r:
            self.assertEqual(main(["state", "checkpoint", "--phase", "9", "--tier", "standard"]), 0)
            with open(os.path.join(r.dir, ".dev", "main.json")) as fh:
                data = json.load(fh)
            self.assertEqual(data["phase"], 9)
            self.assertEqual(data["phase_group"], "coding")
            self.assertEqual(data["tier"], "standard")
            self.assertEqual(data["branch"], "main")
            self.assertEqual(len(data["head_sha"]), 40)

    def test_phases_completed_accumulates_and_never_duplicates(self):
        with TempRepo():
            main(["state", "checkpoint", "--phase", "4"])
            main(["state", "checkpoint", "--phase", "9"])
            main(["state", "checkpoint", "--phase", "4"])
            with open(os.path.join(".dev", "main.json")) as fh:
                data = json.load(fh)
            self.assertEqual(data["phases_completed"], [4, 9])

    def test_out_of_range_phase_is_refused(self):
        with TempRepo():
            self.assertEqual(main(["state", "checkpoint", "--phase", "17"]), 2)
            self.assertFalse(os.path.exists(".dev"))

    def test_attempt_history_records_failures_so_a_retry_need_not_relearn(self):
        with TempRepo():
            main(["state", "checkpoint", "--phase", "9",
                  "--attempt", "patch the resolver", "--outcome", "failure"])
            main(["state", "checkpoint", "--phase", "9",
                  "--attempt", "replace the resolver", "--outcome", "success"])
            with open(os.path.join(".dev", "main.json")) as fh:
                data = json.load(fh)
            self.assertEqual(len(data["attempts"]), 2)
            self.assertEqual(data["attempts"][0]["outcome"], "failure")
            self.assertEqual(data["attempts"][1]["approach"], "replace the resolver")

    def test_tier_survives_a_later_checkpoint_that_omits_it(self):
        with TempRepo():
            main(["state", "checkpoint", "--phase", "2", "--tier", "deep"])
            main(["state", "checkpoint", "--phase", "3"])
            with open(os.path.join(".dev", "main.json")) as fh:
                self.assertEqual(json.load(fh)["tier"], "deep")


class VerifyTests(unittest.TestCase):
    def test_missing_state_is_reported_not_treated_as_valid(self):
        with TempRepo():
            self.assertEqual(main(["state", "verify"]), 1)

    def test_fresh_checkpoint_verifies_clean(self):
        with TempRepo():
            main(["state", "checkpoint", "--phase", "5"])
            self.assertEqual(main(["state", "verify"]), 0)

    def test_a_new_commit_makes_state_stale_so_git_wins(self):
        with TempRepo() as r:
            main(["state", "checkpoint", "--phase", "5"])
            with open(os.path.join(r.dir, "f.txt"), "a") as fh:
                fh.write("more\n")
            git(["add", "-A"], r.dir)
            git(["commit", "-qm", "second"], r.dir)
            self.assertEqual(main(["state", "verify"]), 1)

    def test_read_of_an_unknown_branch_fails_rather_than_inventing(self):
        with TempRepo():
            self.assertEqual(main(["state", "read", "--branch", "nope"]), 1)


class DoctorTests(unittest.TestCase):
    def test_doctor_warns_when_state_dir_is_not_ignored(self):
        with TempRepo():
            self.assertEqual(main(["doctor"]), 1)

    def test_doctor_never_edits_the_repos_gitignore(self):
        with TempRepo() as r:
            main(["doctor"])
            self.assertFalse(os.path.exists(os.path.join(r.dir, ".gitignore")))


class DotDevIgnoresItself(unittest.TestCase):
    """.dev/ keeps itself out of git with its own .gitignore; the repo's is never touched."""

    def test_a_checkpoint_is_ignored_without_a_repo_gitignore(self):
        with TempRepo() as r:
            main(["state", "checkpoint", "--phase", "1"])
            ignored = subprocess.run(["git", "check-ignore", "-q", ".dev/main.json"], cwd=r.dir)
            self.assertEqual(ignored.returncode, 0)
            self.assertFalse(os.path.exists(os.path.join(r.dir, ".gitignore")))

    def test_an_existing_dot_dev_gitignore_is_left_alone(self):
        with TempRepo() as r:
            os.makedirs(os.path.join(r.dir, ".dev"))
            with open(os.path.join(r.dir, ".dev", ".gitignore"), "w") as fh:
                fh.write("mine\n")
            main(["state", "checkpoint", "--phase", "1"])
            with open(os.path.join(r.dir, ".dev", ".gitignore")) as fh:
                self.assertEqual(fh.read(), "mine\n")


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
