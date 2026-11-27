"""Tests for the launcher "Fetch, mark and test the public transcripts": it asks for one typed yes and runs
the fetch, mark and test launchers in order. The three steps are stand-ins that write down that they ran
and exit with the code a test asks for, so nothing is downloaded, marked or trained.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Fetch, mark and test the public transcripts.command"
STEPS = ("Fetch a sample of public transcripts.command", "Mark the public transcripts.command",
         "Test the public marks.command")
STEP = """#!/bin/bash
echo "$(basename "$0") chain=${TEACH_CHAIN:-}" >> "$CALLS"
case "$(basename "$0")" in
  Fetch*) exit "${FETCH_CODE:-0}" ;;
  Mark*) exit "${MARK_CODE:-0}" ;;
  Test*) mkdir -p "$HOME/Storyteller Lofi/PodcastTeachingPublicTest"
         echo "table: stand-in" > "$HOME/Storyteller Lofi/PodcastTeachingPublicTest/COMPARE.txt"
         exit "${TEST_CODE:-0}" ;;
esac
"""


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.tools = os.path.join(self.root, "tools")
        os.makedirs(self.tools)
        shutil.copyfile(os.path.join(HERE, NAME), os.path.join(self.tools, NAME))
        for name in STEPS:
            path = os.path.join(self.tools, name)
            with open(path, "w") as handle:
                handle.write(STEP.replace('code="$STEP_CODES"\n', ""))
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.home = os.path.join(self.root, "home")
        os.makedirs(self.home)
        self.calls = os.path.join(self.root, "calls.txt")

    def run_launcher(self, typed="yes\n\n", **extra):
        env = {"HOME": self.home, "PATH": "/usr/bin:/bin", "CALLS": self.calls}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(self.tools, NAME)], input=typed, env=env,
                              capture_output=True, text=True, timeout=60)

    def ran(self):
        if not os.path.exists(self.calls):
            return []
        with open(self.calls) as handle:
            return [line.strip() for line in handle if line.strip()]

    def test_the_notice_names_the_cap_and_the_terms_before_it_asks(self):
        result = self.run_launcher("no\n\n")
        self.assertIn("never more than $100", result.stdout)
        self.assertIn("research and educational use only", result.stdout)

    def test_nothing_runs_without_a_typed_yes(self):
        result = self.run_launcher("no\n\n")
        self.assertIn("did not type yes", result.stdout)
        self.assertEqual(self.ran(), [])

    def test_with_a_yes_it_runs_the_three_steps_in_order_as_a_chain(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.ran(), [name + " chain=1" for name in STEPS])
        self.assertIn("table: stand-in", result.stdout)
        self.assertIn("All three steps are done", result.stdout)

    def test_a_failed_fetch_stops_before_marking(self):
        result = self.run_launcher(FETCH_CODE="1")
        self.assertEqual(self.ran(), [STEPS[0] + " chain=1"])
        self.assertIn("Stopped at step 1", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_marking_that_ran_out_of_allowance_stops_before_the_test(self):
        result = self.run_launcher(MARK_CODE="3")
        self.assertEqual(len(self.ran()), 2)
        self.assertIn("Stopped at step 2", result.stdout)
        self.assertEqual(result.returncode, 3)

    def test_marking_that_reached_the_cap_still_tests_what_was_marked(self):
        result = self.run_launcher(MARK_CODE="5")
        self.assertEqual(len(self.ran()), 3)
        self.assertIn("spending limit", result.stdout)
        self.assertEqual(result.returncode, 0)

    def test_marking_with_failed_episodes_still_tests_the_rest(self):
        result = self.run_launcher(MARK_CODE="6")
        self.assertEqual(len(self.ran()), 3)
        self.assertIn("failed to be marked", result.stdout)

    def test_a_failed_test_is_said_and_marking_is_kept(self):
        result = self.run_launcher(TEST_CODE="2")
        self.assertIn("Stopped at step 3", result.stdout)
        self.assertEqual(result.returncode, 2)

    def test_a_missing_step_is_said_before_anything_runs(self):
        os.remove(os.path.join(self.tools, STEPS[1]))
        result = self.run_launcher()
        self.assertIn("A step is missing", result.stdout)
        self.assertEqual(self.ran(), [])


if __name__ == "__main__":
    unittest.main()
