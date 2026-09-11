#!/usr/bin/env python3
"""Tests for `dev ui --serve` — PYTHONPATH=. python3 test-projects/state/test_dev_ui_serve.py

The served board lets a card be dragged. These pin which drags become writes, that the column is
re-derived from gh rather than trusted from the page, and that only this machine can ask for one.
"""

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts import dev as _dev  # noqa: E402
from scripts.dev import plan_board_move, resolve_active_milestone, ui_request_allowed  # noqa: E402


def card(col, n=5, epic=False):
    c = {"number": n, "title": "t", "column": col}
    if epic:
        c["epic"] = {"done": 0, "total": 2, "startable": True}
    return c


class WhichDragsBecomeWrites(unittest.TestCase):
    def test_backlog_to_queue_joins_the_active_milestone(self):
        argv, _ = plan_board_move(card("backlog"), "queue", "v1")
        self.assertEqual(argv, ["issue", "edit", "5", "--milestone", "v1"])

    def test_queue_to_backlog_leaves_it(self):
        argv, _ = plan_board_move(card("queue"), "backlog", "v1")
        self.assertEqual(argv, ["issue", "edit", "5", "--remove-milestone"])

    def test_queueing_with_no_active_milestone_is_refused(self):
        argv, why = plan_board_move(card("backlog"), "queue", None)
        self.assertIsNone(argv)
        self.assertIn("milestone", why)

    def test_a_git_derived_card_cannot_be_dragged(self):
        for col in ("in_progress", "pr_created", "human_review", "deferred"):
            argv, why = plan_board_move(card(col), "backlog", "v1")
            self.assertIsNone(argv, col)
            self.assertIn("git", why)

    def test_nothing_can_be_dropped_into_a_git_derived_column(self):
        argv, _ = plan_board_move(card("backlog"), "in_progress", "v1")
        self.assertIsNone(argv)

    def test_cancel_closes_as_not_planned_with_the_reason_as_a_comment(self):
        argv, _ = plan_board_move(card("backlog"), "cancel", "v1", reason="duplicate of #3")
        self.assertEqual(argv, ["issue", "close", "5", "--reason", "not planned",
                                "--comment", "duplicate of #3"])

    def test_cancel_without_a_reason_is_refused(self):
        argv, why = plan_board_move(card("backlog"), "cancel", "v1", reason="  ")
        self.assertIsNone(argv)
        self.assertIn("reason", why)

    def test_an_epic_is_never_cancelled_from_the_board(self):
        """Its children need 7.1's explicit cascade / re-parent / orphan choice first."""
        argv, why = plan_board_move(card("backlog", epic=True), "cancel", "v1", reason="x")
        self.assertIsNone(argv)
        self.assertIn("dev:kanban", why)

    def test_dropping_where_it_already_is_writes_nothing(self):
        self.assertIsNone(plan_board_move(card("queue"), "queue", "v1")[0])

    def test_delete_is_not_a_board_action(self):
        self.assertIsNone(plan_board_move(card("backlog"), "delete", "v1")[0])


class ActiveMilestone(unittest.TestCase):
    """The same rule dev:roadmap states: nearest due date, else the oldest open; a tie is asked."""

    def test_nearest_due_date_wins(self):
        ms = [{"title": "late", "due_on": "2026-12-01T00:00:00Z", "created_at": "2026-01-01"},
              {"title": "soon", "due_on": "2026-10-01T00:00:00Z", "created_at": "2026-02-01"},
              {"title": "undated", "due_on": None, "created_at": "2025-01-01"}]
        self.assertEqual(resolve_active_milestone(ms)[0], "soon")

    def test_with_no_due_dates_the_oldest_open_wins(self):
        ms = [{"title": "new", "due_on": None, "created_at": "2026-05-01"},
              {"title": "old", "due_on": None, "created_at": "2026-01-01"}]
        self.assertEqual(resolve_active_milestone(ms)[0], "old")

    def test_a_tie_is_not_silently_broken(self):
        ms = [{"title": "a", "due_on": "2026-10-01T00:00:00Z"},
              {"title": "b", "due_on": "2026-10-01T00:00:00Z"}]
        title, why = resolve_active_milestone(ms)
        self.assertIsNone(title)
        self.assertIn("--milestone", why)

    def test_no_open_milestone_means_no_queue(self):
        self.assertIsNone(resolve_active_milestone([])[0])


class OnlyThisMachine(unittest.TestCase):
    def test_right_host_and_token_is_allowed(self):
        self.assertTrue(ui_request_allowed({"Host": "127.0.0.1:8000", "X-Dev-Token": "t"}, "t", 8000))
        self.assertTrue(ui_request_allowed({"Host": "localhost:8000", "X-Dev-Token": "t"}, "t", 8000))

    def test_a_foreign_host_is_refused_even_with_the_token(self):
        """DNS rebinding: a page on evil.com resolving to 127.0.0.1 still sends Host: evil.com."""
        self.assertFalse(ui_request_allowed({"Host": "evil.com:8000", "X-Dev-Token": "t"}, "t", 8000))

    def test_a_missing_or_wrong_token_is_refused(self):
        self.assertFalse(ui_request_allowed({"Host": "127.0.0.1:8000"}, "t", 8000))
        self.assertFalse(ui_request_allowed({"Host": "127.0.0.1:8000", "X-Dev-Token": "x"}, "t", 8000))


class ServedEndToEnd(unittest.TestCase):
    """A real server on a free port, gh stubbed: the board it re-reads decides, not the request."""

    def setUp(self):
        import subprocess, tempfile
        self.dir = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", self.dir], check=True)
        self.writes = []
        self.real = (_dev.collect_board, _dev.gh_write)
        _dev.collect_board = lambda root, milestone=None: {
            "active_milestone": "v1",
            "columns": {"backlog": [card("backlog", 5)], "in_progress": [card("in_progress", 6)],
                        "queue": []}}
        _dev.gh_write = lambda argv: self.writes.append(argv) or (True, "")
        os.makedirs(os.path.join(self.dir, _dev.UI_DIR))
        with open(os.path.join(self.dir, _dev.UI_DIR, "board.html"), "w") as fh:
            fh.write(_dev.render_ui_html("board", _dev.collect_board(self.dir), {}))
        self.server, self.token = _dev.make_ui_server(self.dir, 0, None)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        import shutil
        self.server.shutdown()
        self.server.server_close()
        _dev.collect_board, _dev.gh_write = self.real
        shutil.rmtree(self.dir, ignore_errors=True)

    def post(self, body, token=None):
        req = urllib.request.Request(
            "http://127.0.0.1:%d/api/move" % self.port, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json", "X-Dev-Token": token or self.token})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    def test_a_valid_drag_runs_exactly_one_gh_write(self):
        status, body = self.post({"number": 5, "to": "queue"})
        self.assertEqual(status, 200, body)
        self.assertEqual(self.writes, [["issue", "edit", "5", "--milestone", "v1"]])

    def test_the_page_cannot_lie_about_a_cards_column(self):
        """#6 is in flight per gh; a request claiming otherwise is refused, and nothing is written."""
        status, _ = self.post({"number": 6, "to": "queue", "column": "backlog"})
        self.assertEqual(status, 409)
        self.assertEqual(self.writes, [])

    def test_a_wrong_token_writes_nothing(self):
        status, _ = self.post({"number": 5, "to": "queue"}, token="nope")
        self.assertEqual(status, 403)
        self.assertEqual(self.writes, [])

    def test_served_board_carries_the_token_and_the_static_file_does_not(self):
        with urllib.request.urlopen("http://127.0.0.1:%d/board.html" % self.port) as r:
            self.assertIn(self.token, r.read().decode())
        with open(os.path.join(self.dir, _dev.UI_DIR, "board.html")) as fh:
            self.assertNotIn(self.token, fh.read())

    def test_only_the_generated_pages_are_served(self):
        for path in ("/../.git/config", "/board.json", "/x.html"):
            try:
                urllib.request.urlopen("http://127.0.0.1:%d%s" % (self.port, path))
                self.fail("served %s" % path)
            except urllib.error.HTTPError as e:
                self.assertEqual(e.code, 404, path)


class BoardMarkup(unittest.TestCase):
    def test_cards_and_columns_carry_what_the_drag_script_needs(self):
        html = _dev.render_ui_html("board", {"columns": {"backlog": [card("backlog", 9)]}}, {})
        self.assertIn('data-col="backlog"', html)
        self.assertIn('data-n="9"', html)

    def test_the_static_page_says_how_to_make_it_draggable(self):
        html = _dev.render_ui_html("board", {"columns": {}}, {})
        self.assertIn("dev ui --serve", html)

    def test_the_board_names_the_milestone_its_queue_is(self):
        html = _dev.render_ui_html("board", {"columns": {}, "active_milestone": "v1",
                                             "active_why": "nearest due date"}, {})
        self.assertIn("v1", html)


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
