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


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
