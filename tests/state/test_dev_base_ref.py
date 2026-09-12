#!/usr/bin/env python3
"""Tests for the base `dev board` measures against — run with: PYTHONPATH=. python3 tests/state/test_dev_base_ref.py"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.dev import origin_ref, run  # noqa: E402


def git(args, cwd):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"] + args,
                   cwd=cwd, capture_output=True, text=True, check=True)


class OriginRef(unittest.TestCase):
    """A branch merged on the remote, as a pull request merged on GitHub is, while the local base stayed behind."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.app = os.path.join(self.dir, "app")
        origin = os.path.join(self.dir, "origin.git")
        git(["init", "-q", "--bare", origin], self.dir)
        git(["init", "-q", "-b", "main", self.app], self.dir)
        with open(os.path.join(self.app, "f.txt"), "w") as fh:
            fh.write("x\n")
        git(["add", "-A"], self.app)
        git(["commit", "-qm", "init"], self.app)
        git(["remote", "add", "origin", origin], self.app)
        git(["push", "-q", "origin", "main"], self.app)
        git(["switch", "-q", "-c", "feat"], self.app)
        with open(os.path.join(self.app, "g.txt"), "w") as fh:
            fh.write("y\n")
        git(["add", "-A"], self.app)
        git(["commit", "-qm", "feature"], self.app)
        git(["switch", "-q", "--detach", "main"], self.app)
        git(["merge", "-q", "--no-ff", "-m", "Merge feat", "feat"], self.app)
        git(["push", "-q", "origin", "HEAD:main"], self.app)
        git(["switch", "-q", "feat"], self.app)

    def test_the_fixture_reproduces_a_local_base_that_lags(self):
        self.assertEqual(run(["git", "rev-list", "--count", "main..feat"], self.app), (0, "1"))

    def test_origins_copy_wins_so_merged_work_counts_as_merged(self):
        ref = origin_ref("main", self.app)
        self.assertEqual(ref, "refs/remotes/origin/main")
        self.assertEqual(run(["git", "rev-list", "--count", "%s..feat" % ref], self.app), (0, "0"))

    def test_a_base_origin_lacks_is_kept_as_named(self):
        self.assertEqual(origin_ref("develop", self.app), "develop")

    def test_no_base_stays_none(self):
        self.assertIsNone(origin_ref(None, self.app))


if __name__ == "__main__":
    unittest.main()
