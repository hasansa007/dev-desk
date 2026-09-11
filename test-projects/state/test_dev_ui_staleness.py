#!/usr/bin/env python3
"""Tests for `dev ui` staleness — PYTHONPATH=. python3 test-projects/state/test_dev_ui_staleness.py

`dev ui` rebuilds only what is stale. These pin what counts as stale, and that --check never writes.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts import dev as _dev  # noqa: E402
from scripts.dev import UI_DIR, ui_staleness  # noqa: E402


class Repo:
    def __enter__(self):
        self.dir = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", self.dir], check=True)
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, rel, text="x", age=0):
        path = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        if age:
            t = time.time() + age
            os.utime(path, (t, t))
        return path

    def build(self, surface, commit, age=0):
        self.write(os.path.join(UI_DIR, surface + ".json"), json.dumps({"commit": commit}), age)
        self.write(os.path.join(UI_DIR, surface + ".html"), "<html>", age)


class WhatCountsAsStale(unittest.TestCase):
    def test_a_surface_never_built_is_stale(self):
        with Repo() as r:
            self.assertEqual(ui_staleness(r.dir, "insights", "abc1234"), "missing")

    def test_a_file_backed_surface_built_at_head_after_its_inputs_is_fresh(self):
        with Repo() as r:
            r.write("PROJECT_MAP.md", "## A\nx", age=-60)
            r.build("insights", "abc1234")
            self.assertIsNone(ui_staleness(r.dir, "insights", "abc1234"))

    def test_a_new_commit_makes_it_stale_and_says_which(self):
        with Repo() as r:
            r.write("PROJECT_MAP.md", age=-60)
            r.build("insights", "old0000")
            why = ui_staleness(r.dir, "insights", "new1111")
            self.assertIn("old0000", why)
            self.assertIn("new1111", why)

    def test_editing_an_input_after_the_build_makes_it_stale_and_names_the_file(self):
        with Repo() as r:
            r.build("insights", "abc1234", age=-60)
            r.write("PROJECT_MAP.md", "## changed")
            self.assertIn("PROJECT_MAP.md", ui_staleness(r.dir, "insights", "abc1234"))

    def test_github_backed_surfaces_always_need_a_rebuild(self):
        """Nothing local can prove the tracker unchanged, so a same-commit build is not proof."""
        with Repo() as r:
            for s in ("board", "roadmap"):
                r.build(s, "abc1234")
                self.assertIn("GitHub", ui_staleness(r.dir, s, "abc1234"))

    def test_json_without_its_html_is_stale(self):
        with Repo() as r:
            r.build("insights", "abc1234")
            os.remove(os.path.join(r.dir, UI_DIR, "insights.html"))
            self.assertEqual(ui_staleness(r.dir, "insights", "abc1234"), "html missing")

    def test_a_corrupt_snapshot_is_stale_rather_than_a_crash(self):
        with Repo() as r:
            r.write(os.path.join(UI_DIR, "insights.json"), "{not json")
            self.assertEqual(ui_staleness(r.dir, "insights", "abc1234"), "unreadable")

    def test_ideation_reports_appearing_after_the_build_make_it_stale(self):
        with Repo() as r:
            r.build("ideation", "abc1234", age=-60)
            self.assertIsNone(ui_staleness(r.dir, "ideation", "abc1234"))
            r.write(os.path.join("docs", "ideation", "2026-09-11.md"), "## X")
            self.assertIn("docs/ideation", ui_staleness(r.dir, "ideation", "abc1234"))


class CheckMode(unittest.TestCase):
    def _args(self, **kw):
        base = dict(surface=None, milestone=None, open=False, check=False, force=False)
        base.update(kw)
        return argparse.Namespace(**base)

    def test_check_reports_stale_with_a_nonzero_exit_and_writes_nothing(self):
        with Repo() as r:
            cwd = os.getcwd()
            try:
                os.chdir(r.dir)
                rc = _dev.cmd_ui(self._args(check=True))
            finally:
                os.chdir(cwd)
            self.assertEqual(rc, 1)
            self.assertFalse(os.path.exists(os.path.join(r.dir, UI_DIR)))

    def test_check_passes_when_only_the_github_backed_surfaces_would_refresh(self):
        """board and roadmap refresh on every run by design; that alone must not fail --check,
        or its exit code can never be 0 and is useless to a script."""
        with Repo() as r:
            head = _dev.head_sha(r.dir)
            r.write("PROJECT_MAP.md", "## A\nx", age=-60)
            for s in ("board", "roadmap", "insights", "ideation"):
                r.build(s, head, age=-30)
            cwd = os.getcwd()
            try:
                os.chdir(r.dir)
                rc = _dev.cmd_ui(self._args(check=True))
            finally:
                os.chdir(cwd)
            self.assertEqual(rc, 0)

    def test_plain_ui_skips_a_fresh_file_backed_surface(self):
        with Repo() as r:
            r.write("PROJECT_MAP.md", "## A\nx", age=-60)
            r.build("insights", _dev.head_sha(r.dir), age=-30)
            before = os.path.getmtime(os.path.join(r.dir, UI_DIR, "insights.json"))
            real = _dev.collect_insights
            _dev.collect_insights = lambda root: self.fail("a fresh surface was rebuilt")
            cwd = os.getcwd()
            try:
                os.chdir(r.dir)
                _dev.cmd_ui(self._args())
            finally:
                os.chdir(cwd)
                _dev.collect_insights = real
            self.assertEqual(before, os.path.getmtime(os.path.join(r.dir, UI_DIR, "insights.json")))

    def test_force_rebuilds_even_a_fresh_surface(self):
        with Repo() as r:
            r.write("PROJECT_MAP.md", "## A\nx", age=-60)
            r.build("insights", _dev.head_sha(r.dir), age=-30)
            called = []
            real = _dev.collect_insights
            _dev.collect_insights = lambda root: called.append(root) or {"sections": []}
            cwd = os.getcwd()
            try:
                os.chdir(r.dir)
                _dev.cmd_ui(self._args(surface="insights", force=True))
            finally:
                os.chdir(cwd)
                _dev.collect_insights = real
            self.assertEqual(len(called), 1)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
