"""shared/board-rules.json against scripts/dev.py — the Python half of ADR 0055's registry.

The Swift half is apps/desk/DeskCore/Tests/DeskCoreTests/BoardConformanceTests.swift. Both read the same
file and both fail on a rule they do not bind, so a rule added to one reader alone cannot go green.
"""
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import dev  # noqa: E402

RULES = json.load(open(os.path.join(ROOT, "shared", "board-rules.json"), encoding="utf-8"))


def _issue(case):
    return {"number": case.get("number", 1), "title": case.get("title", ""),
            "body": case.get("body", ""), "updatedAt": case.get("updatedAt", ""),
            "labels": [{"name": n} for n in case.get("labels", [])]}


def _agent_prompt(case):
    root = case["skill_root"]
    number = case["task_number"]
    return dev.build_prompt(os.path.join(root, "SKILL.md"), "dev",
                            ["#%d" % number] if number is not None else [])


# Every rule in the registry needs a line here, which is what makes a missing one a failure.
BINDINGS = {
    "branch_matches": lambda c: dev.branch_matches(c["name"], c["number"]),
    "closed_issues": lambda c: sorted(set(dev.closed_issues(c["body"]))),
    "priority_rank": lambda c: dev.priority_rank(_issue(c)),
    "slice_rank": lambda c: dev.slice_rank(_issue(c)),
    "is_decomposed_epic": lambda c: not dev.is_startable(
        _issue(c), len([1 for _, done in dev.parse_epic_children(c["body"]) if not done])),
    "order_next": lambda c: [i["number"] for i in dev.order_next([_issue(i) for i in c["issues"]])],
    "agent_prompt": _agent_prompt,
}


class BoardConformance(unittest.TestCase):
    def test_every_registered_rule_is_bound(self):
        registered = {k for k in RULES if k != "_"}
        self.assertEqual(registered - set(BINDINGS), set(),
                         "shared/board-rules.json names a rule scripts/dev.py does not implement")
        self.assertEqual(set(BINDINGS) - registered, set(),
                         "a binding here has no rule in shared/board-rules.json")

    def test_every_case_matches(self):
        for name in sorted(k for k in RULES if k != "_"):
            for i, case in enumerate(RULES[name]["cases"]):
                with self.subTest(rule=name, case=i, input=case["in"]):
                    self.assertEqual(BINDINGS[name](case["in"]), case["out"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
