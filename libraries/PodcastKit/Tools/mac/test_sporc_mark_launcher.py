"""Tests for the launcher "Mark the public transcripts": the Mac's python3 is a stand-in that writes down
how it was called and exits with the code a test asks for, so nothing is marked and no Claude is used.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Mark the public transcripts.command"
CAFFEINATE = """#!/bin/bash
shift
exec "$@"
"""
PYTHON3 = """#!/bin/bash
echo "$*" >> "$CALLS"
exit "${STAND_IN_CODE:-0}"
"""


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        self.calls = os.path.join(self.root, "calls.txt")
        for name, text in (("python3", PYTHON3), ("caffeinate", CAFFEINATE)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as handle:
                handle.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeachingSporc")

    def sample(self):
        os.makedirs(self.folder)
        with open(os.path.join(self.folder, "episodes.json"), "w") as handle:
            handle.write("{}")

    def run_launcher(self, **extra):
        env = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin", "CALLS": self.calls}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(HERE, NAME)], input="\n", env=env,
                              capture_output=True, text=True, timeout=60)

    def call(self):
        with open(self.calls) as handle:
            return handle.read()

    def test_without_the_sample_it_says_to_fetch_it_first(self):
        result = self.run_launcher()
        self.assertIn("Fetch a sample of public transcripts", result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(os.path.exists(self.calls))

    def test_marks_the_sample_folder_under_its_own_budget_and_cap(self):
        self.sample()
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout)
        text = self.call()
        self.assertIn("teach_label.py", text)
        self.assertIn(self.folder, text)
        for part in ("--limit 500", "--cap 100", "--budget sporc-1", "--wait-hours 12"):
            self.assertIn(part, text)
        self.assertNotIn("--yes", text)
        self.assertNotIn("PodcastTeaching/", text)

    def test_the_numbers_can_be_changed_and_bad_ones_are_ignored(self):
        self.sample()
        self.run_launcher(TEACH_SPORC_LIMIT="30", TEACH_SPORC_CAP="lots", TEACH_SPORC_BUDGET="a b")
        text = self.call()
        for part in ("--limit 30", "--cap 100", "--budget sporc-1"):
            self.assertIn(part, text)

    def test_each_exit_code_has_its_own_message(self):
        self.sample()
        for code, words in ((5, "spending limit"), (6, "episodes failed"), (3, "usage allowance"),
                            (4, "did not type yes"), (2, "not set up"), (0, "Done")):
            result = self.run_launcher(STAND_IN_CODE=str(code))
            self.assertIn(words, result.stdout, code)


if __name__ == "__main__":
    unittest.main()
