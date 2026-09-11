#!/usr/bin/env python3
"""Tests for `dev ui` — PYTHONPATH=. python3 test-projects/state/test_dev_ui.py

ui/ is generated output. These cover the parts that decide what a reader sees: the heading split,
escaping, and that every surface renders the provenance a stale file must carry.
"""

import os
import sys
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.dev import (  # noqa: E402
    UI_SURFACES,
    _esc,
    _headings,
    render_ui_html,
)

META = {"repo": "you/repo", "commit": "abcdef1234567890", "generated_at": "2026-09-11T00:00:00+00:00"}


class HeadingSplit(unittest.TestCase):
    def test_splits_on_h2_and_keeps_the_lines_under_each(self):
        out = _headings("# title\n\n## One\nalpha\n\n## Two\nbeta\ngamma\n")
        self.assertEqual([h["heading"] for h in out], ["One", "Two"])
        self.assertEqual(out[1]["lines"], ["beta", "gamma"])

    def test_content_before_the_first_heading_is_dropped_not_misfiled(self):
        self.assertEqual(_headings("preamble\nmore\n"), [])

    def test_h1_and_h3_are_not_section_boundaries(self):
        out = _headings("## Real\n### Sub\ntext\n")
        self.assertEqual(len(out), 1)
        self.assertIn("### Sub", out[0]["lines"])


class Escaping(unittest.TestCase):
    def test_markup_in_data_cannot_reach_the_page_as_markup(self):
        self.assertEqual(_esc('<img src=x onerror="a">'),
                         "&lt;img src=x onerror=&quot;a&quot;&gt;")

    def test_an_issue_title_with_html_is_escaped_in_the_render(self):
        data = {"columns": {"backlog": [{"number": 1, "title": "<script>alert(1)</script>"}]}}
        html = render_ui_html("board", data, META)
        self.assertNotIn("<script>", html)
        self.assertIn("&lt;script&gt;", html)


class Provenance(unittest.TestCase):
    def test_every_surface_renders_the_commit_it_was_built_from(self):
        for s in UI_SURFACES:
            html = render_ui_html(s, {}, META)
            self.assertIn("abcdef12", html, "%s lost its commit" % s)
            self.assertIn("2026-09-11", html, "%s lost its timestamp" % s)

    def test_every_surface_says_it_is_not_authoritative(self):
        for s in UI_SURFACES:
            self.assertIn("Never read back as truth", render_ui_html(s, {}, META))

    def test_an_unavailable_surface_says_why_rather_than_rendering_empty(self):
        html = render_ui_html("board", {"unavailable": "gh not authenticated"}, META)
        self.assertIn("gh not authenticated", html)
        self.assertNotIn("BACKLOG", html)


class BoardRender(unittest.TestCase):
    def test_columns_and_counts_appear(self):
        data = {"columns": {"backlog": [{"number": 7, "title": "a thing"}], "done": []}}
        html = render_ui_html("board", data, META)
        self.assertIn("BACKLOG", html)
        self.assertIn("#7", html)
        self.assertIn("nothing here", html)  # the empty column says so

    def test_a_phase_is_labelled_advisory_wherever_it_is_shown(self):
        data = {"columns": {"in_progress": [{"number": 3, "title": "x", "phase": "coding"}]}}
        self.assertIn("coding · advisory", render_ui_html("board", data, META))

    def test_no_phase_means_no_phase_claim_in_the_html(self):
        data = {"columns": {"in_progress": [{"number": 3, "title": "x"}]}}
        self.assertNotIn("advisory", render_ui_html("board", data, META))


class OtherSurfaces(unittest.TestCase):
    def test_roadmap_shows_epic_progress(self):
        data = {"milestones": [{"title": "M1", "open": 2, "closed": 1}],
                "epics": [{"number": 9, "title": "big", "progress": {"done": 1, "total": 4}}]}
        html = render_ui_html("roadmap", data, META)
        self.assertIn("M1", html)
        self.assertIn("1/4", html)

    def test_reports_with_no_directory_render_the_note_not_a_blank(self):
        html = render_ui_html("ideation", {"reports": [], "note": "no docs/ideation/ yet"}, META)
        self.assertIn("no docs/ideation/ yet", html)

    def test_insights_renders_project_map_sections(self):
        data = {"sections": [{"heading": "TECH_STACK", "lines": ["python"]}]}
        html = render_ui_html("insights", data, META)
        self.assertIn("TECH_STACK", html)
        self.assertIn("python", html)


class OpenFlag(unittest.TestCase):
    def test_open_hands_a_file_url_to_the_browser_and_nothing_else(self):
        """--open must use stdlib webbrowser with a file:// URL — no shell, no platform switch."""
        import argparse, tempfile, subprocess, webbrowser
        from scripts import dev as _dev
        d = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", d], check=True)
        seen = []
        real_open, real_collect = webbrowser.open, _dev.collect_board
        webbrowser.open = lambda url: seen.append(url) or True
        _dev.collect_board = lambda root, milestone=None: {"columns": {}}
        cwd = os.getcwd()
        try:
            os.chdir(d)
            rc = _dev.cmd_ui(argparse.Namespace(surface="board", milestone=None, open=True))
        finally:
            os.chdir(cwd)
            webbrowser.open, _dev.collect_board = real_open, real_collect
        self.assertEqual(rc, 0)
        self.assertEqual(len(seen), 1)
        self.assertTrue(seen[0].startswith("file://"))
        self.assertTrue(seen[0].endswith(".dev/ui/board.html"))

    def test_open_with_no_surface_lands_on_the_index(self):
        import argparse, webbrowser
        from scripts import dev as _dev
        seen = []
        real_open = webbrowser.open
        webbrowser.open = lambda url: seen.append(url) or True
        try:
            with StubbedRepo() as d:
                _dev.cmd_ui(argparse.Namespace(surface=None, milestone=None, open=True))
        finally:
            webbrowser.open = real_open
        self.assertTrue(seen[0].endswith(".dev/ui/index.html"))

    def test_without_open_nothing_is_launched(self):
        import argparse, tempfile, subprocess, webbrowser
        from scripts import dev as _dev
        d = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", d], check=True)
        seen = []
        real_open, real_collect = webbrowser.open, _dev.collect_board
        webbrowser.open = lambda url: seen.append(url) or True
        _dev.collect_board = lambda root, milestone=None: {"columns": {}}
        cwd = os.getcwd()
        try:
            os.chdir(d)
            _dev.cmd_ui(argparse.Namespace(surface="board", milestone=None, open=False))
        finally:
            os.chdir(cwd)
            webbrowser.open, _dev.collect_board = real_open, real_collect
        self.assertEqual(seen, [])


class StubbedRepo:
    """A fresh git repo as cwd, with the GitHub-backed collectors stubbed so nothing hits the network."""

    def __enter__(self):
        import subprocess, tempfile
        from scripts import dev as _dev
        self.dev, self.cwd = _dev, os.getcwd()
        self.dir = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", self.dir], check=True)
        self.real = (_dev.collect_board, _dev.collect_roadmap)
        _dev.collect_board = lambda root, milestone=None: {"columns": {"backlog": [
            {"number": 1, "title": "a"}, {"number": 2, "title": "b"}]}}
        _dev.collect_roadmap = lambda: {"milestones": [], "epics": []}
        os.chdir(self.dir)
        return self.dir

    def __exit__(self, *exc):
        import shutil
        os.chdir(self.cwd)
        self.dev.collect_board, self.dev.collect_roadmap = self.real
        shutil.rmtree(self.dir, ignore_errors=True)


def _ui(**kw):
    import argparse
    from scripts import dev as _dev
    base = dict(surface=None, milestone=None, open=False, check=False, force=False)
    base.update(kw)
    return _dev.cmd_ui(argparse.Namespace(**base))


class OneFolder(unittest.TestCase):
    """Everything the CLI generates lives under .dev/, and .dev/ keeps itself out of git."""

    def test_pages_are_written_under_dot_dev(self):
        with StubbedRepo() as d:
            _ui()
            self.assertTrue(os.path.isfile(os.path.join(d, ".dev", "ui", "board.html")))
            self.assertFalse(os.path.exists(os.path.join(d, "ui")))

    def test_dot_dev_ignores_itself_without_touching_the_repo_gitignore(self):
        import subprocess
        with StubbedRepo() as d:
            _ui()
            ignored = subprocess.run(["git", "check-ignore", "-q", ".dev/ui/board.html"], cwd=d)
            self.assertEqual(ignored.returncode, 0)
            self.assertFalse(os.path.exists(os.path.join(d, ".gitignore")))

    def test_an_existing_dot_dev_gitignore_is_left_alone(self):
        with StubbedRepo() as d:
            os.makedirs(os.path.join(d, ".dev"))
            with open(os.path.join(d, ".dev", ".gitignore"), "w") as fh:
                fh.write("mine\n")
            _ui()
            with open(os.path.join(d, ".dev", ".gitignore")) as fh:
                self.assertEqual(fh.read(), "mine\n")

    def test_state_checkpoints_get_the_same_self_ignore(self):
        from scripts.dev import save_state
        with StubbedRepo() as d:
            save_state(d, "feature/x", {"phase": 1})
            self.assertTrue(os.path.isfile(os.path.join(d, ".dev", ".gitignore")))

    def test_a_leftover_root_ui_folder_is_reported_never_deleted(self):
        import io, json
        from contextlib import redirect_stdout
        with StubbedRepo() as d:
            os.makedirs(os.path.join(d, "ui"))
            with open(os.path.join(d, "ui", "board.json"), "w") as fh:
                json.dump({"surface": "board"}, fh)
            out = io.StringIO()
            with redirect_stdout(out):
                _ui()
            self.assertIn("leftover", out.getvalue())
            self.assertTrue(os.path.isfile(os.path.join(d, "ui", "board.json")))

    def test_a_source_folder_named_ui_is_not_mistaken_for_leftovers(self):
        import io
        from contextlib import redirect_stdout
        with StubbedRepo() as d:
            os.makedirs(os.path.join(d, "ui"))
            open(os.path.join(d, "ui", "Button.tsx"), "w").close()
            out = io.StringIO()
            with redirect_stdout(out):
                _ui()
            self.assertNotIn("leftover", out.getvalue())


class Index(unittest.TestCase):
    def _index(self, d):
        with open(os.path.join(d, ".dev", "ui", "index.html"), encoding="utf-8") as fh:
            return fh.read()

    def test_index_links_every_surface(self):
        with StubbedRepo() as d:
            _ui()
            html = self._index(d)
            for s in UI_SURFACES:
                self.assertIn('href="%s.html"' % s, html)

    def test_index_summarises_what_each_page_holds(self):
        with StubbedRepo() as d:
            _ui()
            self.assertIn("2 open", self._index(d))

    def test_a_surface_never_built_says_so_on_the_index(self):
        with StubbedRepo() as d:
            _ui(surface="board")
            self.assertIn("not built yet", self._index(d))

    def test_every_page_links_back_to_the_index_and_its_siblings(self):
        for s in UI_SURFACES:
            html = render_ui_html(s, {}, META)
            self.assertIn('href="index.html"', html, "%s has no way home" % s)
            for other in UI_SURFACES:
                self.assertIn('href="%s.html"' % other, html)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
