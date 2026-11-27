"""Tests for the launcher "Fetch and mark 500 more public transcripts": one typed yes, then the fetch step
(a bigger sample) and the marking step (another $100 under its own budget), as steps of a chain. The two
steps are stand-ins that write down how they were called and exit with the code a test asks for, so
nothing is downloaded or marked and no Claude is used.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Fetch and mark 500 more public transcripts.command"
FETCH = "Fetch a sample of public transcripts.command"
MARK = "Mark the public transcripts.command"
STEP = """#!/bin/bash
echo "$(basename "$0") chain=${TEACH_CHAIN:-} count=${TEACH_SPORC_COUNT:-} limit=${TEACH_SPORC_LIMIT:-} cap=${TEACH_SPORC_CAP:-} budget=${TEACH_SPORC_BUDGET:-}" >> "$CALLS"
case "$(basename "$0")" in
  Fetch*) exit "${FETCH_CODE:-0}" ;;
  Mark*) exit "${MARK_CODE:-0}" ;;
esac
"""


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.tools = os.path.join(self.root, "tools")
        os.makedirs(self.tools)
        shutil.copyfile(os.path.join(HERE, NAME), os.path.join(self.tools, NAME))
        for name in (FETCH, MARK):
            path = os.path.join(self.tools, name)
            with open(path, "w") as handle:
                handle.write(STEP)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.calls = os.path.join(self.root, "calls.txt")

    def run_launcher(self, typed="yes\n\n", **extra):
        env = {"HOME": os.path.join(self.root, "home"), "PATH": "/usr/bin:/bin", "CALLS": self.calls}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(self.tools, NAME)], input=typed, env=env,
                              capture_output=True, text=True, timeout=60)

    def ran(self):
        if not os.path.exists(self.calls):
            return []
        with open(self.calls) as handle:
            return [line.strip() for line in handle if line.strip()]

    def test_the_notice_says_the_money_the_terms_and_that_the_test_is_left_alone(self):
        result = self.run_launcher("no\n\n")
        for words in ("$100 more", "$200", "research and educational use only", "does not touch the test"):
            self.assertIn(words, result.stdout)

    def test_nothing_runs_without_a_typed_yes(self):
        result = self.run_launcher("no\n\n")
        self.assertIn("did not type yes", result.stdout)
        self.assertEqual(self.ran(), [])

    def test_with_a_yes_it_fetches_a_bigger_sample_then_marks_under_its_own_budget(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fetch, mark = self.ran()
        self.assertEqual(fetch, FETCH + " chain=1 count=1000 limit=1000 cap=100 budget=sporc-2")
        self.assertEqual(mark, MARK + " chain=1 count=1000 limit=1000 cap=100 budget=sporc-2")
        self.assertIn("Done", result.stdout)

    def test_it_does_not_run_the_test_step(self):
        self.run_launcher()
        self.assertFalse(any(line.startswith("Test the public marks") for line in self.ran()))

    def test_a_failed_fetch_stops_before_marking(self):
        result = self.run_launcher(FETCH_CODE="1")
        self.assertEqual(len(self.ran()), 1)
        self.assertIn("Stopped at step 1", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_marking_that_reached_the_cap_is_a_normal_end(self):
        result = self.run_launcher(MARK_CODE="5")
        self.assertIn("spending limit", result.stdout)
        self.assertEqual(result.returncode, 0)

    def test_marking_that_ran_out_of_allowance_says_to_double_click_again(self):
        result = self.run_launcher(MARK_CODE="3")
        self.assertIn("double-click again", result.stdout)
        self.assertEqual(result.returncode, 3)

    def test_marking_with_failed_episodes_is_said(self):
        result = self.run_launcher(MARK_CODE="6")
        self.assertIn("failed", result.stdout)
        self.assertEqual(result.returncode, 6)

    def test_a_missing_step_is_said_before_anything_runs(self):
        os.remove(os.path.join(self.tools, MARK))
        result = self.run_launcher()
        self.assertIn("A step is missing", result.stdout)
        self.assertEqual(self.ran(), [])


if __name__ == "__main__":
    unittest.main()
