#!/usr/bin/env python3
"""Tests for `dev board` — run with: PYTHONPATH=. python3 tests/state/test_dev_board.py

The board is pure: issues plus per-issue git facts in, columns out. Every case below is a fixture,
so the classification rules are checked against known input rather than against a live tracker.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts import dev as _dev  # noqa: E402
from scripts.dev import (  # noqa: E402
    build_board,
    classify,
    epic_progress,
    is_startable,
    main,
    order_next,
    parse_epic_children,
    priority_rank,
    resolve_active_milestone,
    slice_rank,
)


def issue(number, title="t", labels=(), updated="2026-01-01", body="", milestone=None):
    return {
        "number": number,
        "title": title,
        "labels": [{"name": n} for n in labels],
        "updatedAt": updated,
        "body": body,
        "milestone": {"title": milestone} if milestone else None,
    }


# The exact shape that produced the wrong answer: four real children as checklist lines, plus an
# unrelated roadmap issue mentioned twice in PROSE. A bare `#N` grep finds five and calls it 1/5.
EPIC_BODY_WITH_PROSE_REFS = """
Some context here. See the Roadmap issue #77 for background.

Roadmap context: #77

## Slices
- [ ] #101
- [ ] #102
- [ ] #103
- [ ] #104
"""


class EpicChildParsing(unittest.TestCase):
    def test_prose_references_are_not_children(self):
        children = parse_epic_children(EPIC_BODY_WITH_PROSE_REFS)
        self.assertEqual([n for n, _ in children], [101, 102, 103, 104])
        self.assertNotIn(77, [n for n, _ in children])

    def test_progress_is_zero_of_four_not_one_of_five(self):
        self.assertEqual(epic_progress(parse_epic_children(EPIC_BODY_WITH_PROSE_REFS)), (0, 4))

    def test_checked_children_count_as_done(self):
        body = "- [x] #1\n- [X] #2\n- [ ] #3\n"
        self.assertEqual(epic_progress(parse_epic_children(body)), (2, 3))

    def test_asterisk_bullets_and_tabs_are_still_checklist_lines(self):
        self.assertEqual(len(parse_epic_children("*\t[ ]\t#9\n  - [ ] #10\n")), 2)

    def test_empty_body_has_no_children(self):
        self.assertEqual(parse_epic_children(""), [])
        self.assertEqual(parse_epic_children(None), [])

    def test_a_link_inside_prose_never_becomes_a_child(self):
        self.assertEqual(parse_epic_children("blocked by #55 and closes #56"), [])


class Startability(unittest.TestCase):
    def test_epic_with_open_children_is_not_startable(self):
        self.assertFalse(is_startable(issue(1, labels=["epic"]), open_children=4))

    def test_epic_with_no_open_children_is_just_an_issue(self):
        self.assertTrue(is_startable(issue(1, labels=["epic"]), open_children=0))

    def test_a_normal_issue_is_always_startable(self):
        self.assertTrue(is_startable(issue(1), open_children=3))


class Ordering(unittest.TestCase):
    def test_unlabelled_sorts_after_p3(self):
        self.assertGreater(priority_rank(issue(1)), priority_rank(issue(2, labels=["P3"])))

    def test_priority_then_slice_then_age(self):
        rows = [
            issue(1, "Slice 2 thing", ["P1"], "2026-01-05"),
            issue(2, "Slice 1 thing", ["P1"], "2026-01-09"),
            issue(3, "later", ["P2"], "2026-01-01"),
            issue(4, "unlabelled", [], "2020-01-01"),
        ]
        self.assertEqual([i["number"] for i in order_next(rows)], [2, 1, 3, 4])

    def test_slice_number_is_read_from_the_title(self):
        self.assertEqual(slice_rank(issue(1, "Slice 3 — do the thing")), 3)
        self.assertEqual(slice_rank(issue(1, "no slice here")), 9999)

    def test_same_priority_and_no_slice_falls_back_to_oldest_first(self):
        rows = [issue(1, "b", ["P2"], "2026-05-05"), issue(2, "a", ["P2"], "2026-01-01")]
        self.assertEqual([i["number"] for i in order_next(rows)], [2, 1])


class Classification(unittest.TestCase):
    def test_a_branch_with_no_unmerged_commits_is_not_in_progress(self):
        self.assertEqual(classify(issue(1), {"unmerged": 0}), "backlog")

    def test_unmerged_commits_mean_in_progress(self):
        self.assertEqual(classify(issue(1), {"unmerged": 3}), "in_progress")

    def test_open_pr_without_a_review_is_pr_created(self):
        facts = {"unmerged": 2, "pr": {"state": "OPEN", "reviewDecision": None}}
        self.assertEqual(classify(issue(1), facts), "pr_created")

    def test_review_requested_moves_it_to_human_review(self):
        facts = {"unmerged": 2, "pr": {"state": "OPEN", "reviewDecision": "CHANGES_REQUESTED"}}
        self.assertEqual(classify(issue(1), facts), "human_review")

    def test_active_milestone_membership_is_the_queue(self):
        self.assertEqual(classify(issue(1, milestone="M1"), {}, active_milestone="M1"), "queue")

    def test_another_milestone_is_not_the_queue(self):
        self.assertEqual(classify(issue(1, milestone="M2"), {}, active_milestone="M1"), "backlog")

    def test_epic_leftover_is_deferred_and_outranks_everything(self):
        self.assertEqual(classify(issue(1, labels=["epic-leftover"]), {"unmerged": 9}), "deferred")


class BoardAssembly(unittest.TestCase):
    def test_unstartable_epic_is_reported_as_progress_but_never_offered(self):
        rows = [issue(1, "Big one", ["epic"], body=EPIC_BODY_WITH_PROSE_REFS)]
        board = build_board(rows, {})
        self.assertEqual(board["columns"]["backlog"], [])
        self.assertEqual(board["epics"][0]["epic"], {"done": 0, "total": 4, "startable": False})

    def test_childless_epic_is_offered_as_work(self):
        board = build_board([issue(2, "Small epic", ["epic"], body="no children")], {})
        self.assertEqual([r["number"] for r in board["columns"]["backlog"]], [2])
        self.assertTrue(board["epics"][0]["epic"]["startable"])

    def test_phase_from_state_is_carried_and_flagged_advisory(self):
        board = build_board([issue(5)], {5: {"unmerged": 1, "phase_group": "coding"}})
        row = board["columns"]["in_progress"][0]
        self.assertEqual(row["phase"], "coding")
        self.assertTrue(row["phase_advisory"])

    def test_no_phase_state_means_no_phase_claim_at_all(self):
        board = build_board([issue(5)], {5: {"unmerged": 1}})
        self.assertNotIn("phase", board["columns"]["in_progress"][0])

    def test_counts_cover_every_column(self):
        board = build_board([issue(1), issue(2, labels=["epic-leftover"])], {})
        self.assertEqual(board["counts"]["backlog"], 1)
        self.assertEqual(board["counts"]["deferred"], 1)

    def test_empty_tracker_yields_empty_columns_not_an_error(self):
        board = build_board([], {})
        self.assertEqual(sum(board["counts"].values()), 0)


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

    def test_the_plan_order_wins_over_due_dates(self):
        ms = [{"title": "soon", "due_on": "2026-10-01T00:00:00Z", "created_at": "2026-02-01"},
              {"title": "chosen", "due_on": None, "created_at": "2026-03-01"}]
        title, why = resolve_active_milestone(ms, ["closed-one", "chosen"])
        self.assertEqual(title, "chosen")
        self.assertIn("top of Plan", why)

    def test_work_settings_can_make_the_due_date_decide(self):
        import json, os, tempfile
        plan_order = _dev.plan_order
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, ".devdesk"))
            with open(os.path.join(root, ".devdesk", "plan.json"), "w") as fh:
                json.dump({"titles": ["chosen"]}, fh)
            self.assertEqual(plan_order(root), ["chosen"])
            with open(os.path.join(root, ".devdesk", "work.json"), "w") as fh:
                json.dump({"nextUpFollows": "dueDate"}, fh)
            self.assertEqual(plan_order(root), [])

    def test_p0_ranks_before_p1(self):
        self.assertLess(priority_rank(issue(1, labels=["P0"])), priority_rank(issue(2, labels=["P1"])))

    def test_no_open_milestone_means_no_queue(self):
        self.assertIsNone(resolve_active_milestone([])[0])


class BoardResolvesTheQueue(unittest.TestCase):
    """`dev board` without --milestone applies that rule, so dev:board's QUEUE needs no flag."""

    def setUp(self):
        self.dir, self.cwd = tempfile.mkdtemp(), os.getcwd()
        subprocess.run(["git", "init", "-q", self.dir], check=True)
        os.chdir(self.dir)
        self.real = (_dev._gh_json, _dev._open_milestones)
        issues = [issue(1, milestone="soon"), issue(2, milestone="late"), issue(3)]
        self.milestones = [
            {"title": "late", "due_on": "2026-12-01T00:00:00Z", "created_at": "2026-01-01"},
            {"title": "soon", "due_on": "2026-10-01T00:00:00Z", "created_at": "2026-02-01"}]
        _dev._gh_json = lambda args: issues if args[:2] == ["issue", "list"] else None
        _dev._open_milestones = lambda: self.milestones

    def tearDown(self):
        os.chdir(self.cwd)
        _dev._gh_json, _dev._open_milestones = self.real
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_board(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(main(["board"] + list(argv)), 0)
        return out.getvalue()

    def test_without_the_flag_the_nearest_due_milestone_is_the_queue(self):
        board = json.loads(self.run_board("--json"))
        self.assertEqual([r["number"] for r in board["columns"]["queue"]], [1])
        self.assertEqual(board["active_milestone"], "soon")
        self.assertIn("nearest due date", board["active_why"])

    def test_the_flag_overrides_the_rule(self):
        board = json.loads(self.run_board("--json", "--milestone", "late"))
        self.assertEqual([r["number"] for r in board["columns"]["queue"]], [2])
        self.assertEqual(board["active_why"], "given with --milestone")

    def test_a_failed_milestone_read_says_so_rather_than_posing_as_none(self):
        self.milestones = None
        board = json.loads(self.run_board("--json"))
        self.assertEqual(board["columns"]["queue"], [])
        self.assertIn("could not read milestones", board["active_why"])

    def test_the_text_board_names_the_milestone_its_queue_is(self):
        self.assertIn("QUEUE = milestone soon", self.run_board())


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
