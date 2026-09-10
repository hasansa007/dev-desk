#!/usr/bin/env python3
"""Tests for `dev run` — run with: PYTHONPATH=. python3 test-projects/state/test_dev_run.py"""

import os
import shutil
import sys
import tempfile
import unittest

# Add repo root to import path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from scripts.dev import (  # noqa: E402
    AGENTS,
    UNSUPPORTED,
    build_command,
    build_prompt,
    list_doors,
    resolve_door,
)


class FakeRoot:
    """A skill root with two doors and one stray file, mirroring a real install."""

    def __enter__(self):
        self.dir = tempfile.mkdtemp()
        open(os.path.join(self.dir, "SKILL.md"), "w").write("# root\n")
        for door in ("kanban", "roadmap"):
            os.makedirs(os.path.join(self.dir, "skills", door))
            open(os.path.join(self.dir, "skills", door, "SKILL.md"), "w").write("# %s\n" % door)
        os.makedirs(os.path.join(self.dir, "skills", "notadoor"))
        open(os.path.join(self.dir, "skills", ".DS_Store"), "w").write("junk")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.dir, ignore_errors=True)


class DoorResolution(unittest.TestCase):
    def test_bare_dev_resolves_to_the_root_skill(self):
        with FakeRoot() as r:
            self.assertEqual(resolve_door(r.dir, "dev"), os.path.join(r.dir, "SKILL.md"))
            self.assertEqual(resolve_door(r.dir, None), os.path.join(r.dir, "SKILL.md"))

    def test_a_member_door_resolves_under_skills(self):
        with FakeRoot() as r:
            self.assertEqual(resolve_door(r.dir, "kanban"),
                             os.path.join(r.dir, "skills", "kanban", "SKILL.md"))

    def test_unknown_door_resolves_to_nothing(self):
        with FakeRoot() as r:
            self.assertIsNone(resolve_door(r.dir, "nosuchdoor"))

    def test_a_directory_without_a_skill_file_is_not_a_door(self):
        with FakeRoot() as r:
            self.assertIsNone(resolve_door(r.dir, "notadoor"))


class DoorListing(unittest.TestCase):
    def test_stray_files_are_not_listed_as_doors(self):
        with FakeRoot() as r:
            doors = list_doors(r.dir)
            self.assertEqual(doors, ["kanban", "roadmap"])
            self.assertNotIn(".DS_Store", doors)
            self.assertNotIn("notadoor", doors)

    def test_a_root_with_no_skills_directory_lists_nothing(self):
        d = tempfile.mkdtemp()
        try:
            self.assertEqual(list_doors(d), [])
        finally:
            shutil.rmtree(d, ignore_errors=True)


class CommandConstruction(unittest.TestCase):
    def test_claude_uses_print_mode(self):
        self.assertEqual(build_command("claude", "P"), ["claude", "-p", "P"])

    def test_codex_uses_the_exec_subcommand(self):
        self.assertEqual(build_command("codex", "P"), ["codex", "exec", "P"])

    def test_the_prompt_names_the_door_path_so_the_agent_reads_the_real_file(self):
        p = build_prompt("/x/SKILL.md", "kanban", [])
        self.assertIn("/x/SKILL.md", p)
        self.assertNotIn("Arguments:", p)

    def test_arguments_are_appended_only_when_present(self):
        self.assertIn("Arguments: show all", build_prompt("/x/SKILL.md", "roadmap", ["show", "all"]))

    def test_the_prompt_is_the_last_argument_so_quoting_stays_simple(self):
        cmd = build_command("claude", "a prompt with spaces")
        self.assertEqual(cmd[-1], "a prompt with spaces")


class AgentSupport(unittest.TestCase):
    def test_only_verified_invocations_are_offered(self):
        self.assertEqual(sorted(AGENTS), ["claude", "codex"])

    def test_unverified_agents_are_listed_with_a_reason_rather_than_guessed(self):
        self.assertIn("antigravity", UNSUPPORTED)
        self.assertIn("gemini", UNSUPPORTED)
        for name, reason in UNSUPPORTED.items():
            self.assertTrue(reason.strip(), "%s must say WHY it is unsupported" % name)

    def test_no_agent_appears_in_both_tables(self):
        self.assertEqual(set(AGENTS) & set(UNSUPPORTED), set())


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=0).result
    total = result.testsRun
    bad = len(result.failures) + len(result.errors)
    print("=" * 64)
    print("ALL %d/%d TESTS PASSED!" % (total, total) if not bad
          else "%d/%d FAILED" % (bad, total))
    print("=" * 64)
    sys.exit(1 if bad else 0)
