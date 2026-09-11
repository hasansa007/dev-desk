#!/usr/bin/env python3
"""Tests for the Projects v2 adapter — PYTHONPATH=. python3 test-projects/state/test_dev_project.py

The adapter's core is pure: computed board + current project items in, the edits needed out. The
live path cannot be tested without a `project` token scope, so everything decidable is a fixture.
"""

import os
import sys
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.dev import (  # noqa: E402
    STATUS_CANDIDATES,
    find_status_field,
    match_option,
    plan_project_sync,
)

OPTIONS = [
    {"id": "o1", "name": "Backlog"},
    {"id": "o2", "name": "In Progress"},
    {"id": "o3", "name": "In review"},
    {"id": "o4", "name": "Done"},
]


def item(number, status, iid=None):
    return {"id": iid or ("i%d" % number), "status": status, "content": {"number": number}}


def board(**columns):
    cols = {k: [{"number": n, "title": "t"} for n in v] for k, v in columns.items()}
    return {"columns": cols}


class StatusField(unittest.TestCase):
    def test_prefers_the_field_actually_named_status(self):
        fields = [{"type": "ProjectV2SingleSelectField", "name": "Size"},
                  {"type": "ProjectV2SingleSelectField", "name": "Status"}]
        self.assertEqual(find_status_field(fields)["name"], "Status")

    def test_falls_back_to_the_first_single_select(self):
        fields = [{"type": "ProjectV2Field", "name": "Title"},
                  {"type": "ProjectV2SingleSelectField", "name": "Stage"}]
        self.assertEqual(find_status_field(fields)["name"], "Stage")

    def test_a_project_with_no_single_select_has_no_status_field(self):
        self.assertIsNone(find_status_field([{"type": "ProjectV2Field", "name": "Title"}]))


class OptionMatching(unittest.TestCase):
    def test_matching_ignores_case(self):
        self.assertEqual(match_option("pr_created", OPTIONS)["id"], "o3")  # "In review"

    def test_falls_through_candidates_in_order(self):
        # no "Queue" option here, so queue lands on the first candidate that exists
        opts = OPTIONS + [{"id": "o5", "name": "Ready"}]
        self.assertEqual(match_option("queue", opts)["name"], "Ready")

    def test_queue_never_collapses_onto_backlogs_option(self):
        """A default GitHub board has Todo/In Progress/Done. backlog takes Todo; queue must not,
        or the two columns merge silently and the milestone-as-queue distinction disappears."""
        default = [{"id": "t", "name": "Todo"}, {"id": "p", "name": "In Progress"},
                   {"id": "d", "name": "Done"}]
        self.assertEqual(match_option("backlog", default)["name"], "Todo")
        self.assertIsNone(match_option("queue", default))

    def test_an_unmappable_column_returns_none_rather_than_guessing(self):
        self.assertIsNone(match_option("deferred", OPTIONS))

    def test_every_board_column_has_candidates_declared(self):
        for column in ("backlog", "queue", "in_progress", "pr_created", "human_review", "done"):
            self.assertTrue(STATUS_CANDIDATES.get(column), "%s has no candidates" % column)


class SyncPlan(unittest.TestCase):
    def test_only_items_whose_status_differs_are_edited(self):
        plan = plan_project_sync(board(backlog=[1], in_progress=[2]),
                                 [item(1, "Backlog"), item(2, "Backlog")], OPTIONS)
        self.assertEqual([e["number"] for e in plan["edits"]], [2])
        self.assertEqual(plan["edits"][0]["to"], "In Progress")

    def test_an_already_correct_project_needs_no_edits(self):
        plan = plan_project_sync(board(done=[7]), [item(7, "Done")], OPTIONS)
        self.assertEqual(plan["edits"], [])

    def test_an_issue_not_in_the_project_is_reported_not_invented(self):
        plan = plan_project_sync(board(backlog=[9]), [], OPTIONS)
        self.assertEqual(plan["absent"], [9])
        self.assertEqual(plan["edits"], [])

    def test_an_unmappable_column_is_reported_and_skipped(self):
        plan = plan_project_sync(board(deferred=[3]), [item(3, "Backlog")], OPTIONS)
        self.assertEqual(plan["unmapped"], ["deferred"])
        self.assertEqual(plan["edits"], [])

    def test_an_item_with_no_status_yet_is_an_edit_not_a_match(self):
        plan = plan_project_sync(board(backlog=[4]), [item(4, None)], OPTIONS)
        self.assertEqual(plan["edits"][0]["from"], "(none)")
        self.assertEqual(plan["edits"][0]["to"], "Backlog")

    def test_case_differences_alone_are_not_an_edit(self):
        plan = plan_project_sync(board(pr_created=[5]), [item(5, "IN REVIEW")], OPTIONS)
        self.assertEqual(plan["edits"], [])

    def test_edits_carry_the_ids_item_edit_needs(self):
        plan = plan_project_sync(board(done=[6]), [item(6, "Backlog", iid="ITEM6")], OPTIONS)
        e = plan["edits"][0]
        self.assertEqual(e["item_id"], "ITEM6")
        self.assertEqual(e["option_id"], "o4")

    def test_a_project_item_that_is_not_an_issue_is_ignored(self):
        draft = {"id": "d1", "status": "Backlog", "content": {}}
        plan = plan_project_sync(board(backlog=[1]), [draft, item(1, "Backlog")], OPTIONS)
        self.assertEqual(plan["edits"], [])
        self.assertEqual(plan["absent"], [])


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
