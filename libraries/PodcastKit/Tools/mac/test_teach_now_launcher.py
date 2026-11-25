"""Tests for "Gather deeper and mark now": the "tonight" launcher with the marking allowed at any hour. It
runs with the stand-in programs of test_teach_night_launchers.py on a temporary PATH and home. No Mac, no
network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import subprocess
import unittest

from test_teach_night_launchers import COLLECT, HERE, Setup

NAME = "Gather deeper and mark now.command"


class FilesTests(unittest.TestCase):
    def test_it_is_a_runnable_bash_file_for_bash_3_2(self):
        path = os.path.join(HERE, NAME)
        self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        self.assertEqual(subprocess.run(["bash", "-n", path]).returncode, 0)
        code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
        for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                        r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b", r"\bsed\s+-i\b"):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn("finish()", text)
        self.assertIn('HERE="$(cd "$(dirname "$0")" && pwd)"', text)

    def test_the_readme_lists_it(self):
        with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
            self.assertIn(NAME, f.read())


class NowTests(Setup):
    def test_it_says_the_marking_happens_at_any_hour(self):
        done = self.run_script(NAME, typed="\n")
        self.assertIn("at any hour", done.stdout)
        self.assertNotIn("between 11 at night and 7 in the morning", done.stdout)

    def test_anything_but_yes_starts_nothing(self):
        for typed in ("\n", "no\n", "yes please\n"):
            open(self.calls, "w").close()
            done = self.run_script(NAME, typed=typed)
            self.assertEqual(done.returncode, 0, typed)
            self.assertEqual(self.called(), [], typed)

    def test_a_typed_yes_gathers_deeper_and_marks_between_0_and_24(self):
        done = self.run_script(NAME, typed="yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.python_calls()[0], COLLECT + " --per-show 24 --max-gb 80")
        self.assertEqual(self.labelling(), ["python3 teach_label.py --folder FOLDER --between 0-24 --wait-hours 120 "
                                            "--cap 95 --budget big-run-1 --yes"])

    def test_it_is_noted_in_the_log(self):
        self.run_script(NAME, typed="yes\n")
        self.assertRegex(self.log(), r"gather deeper: newest 24 of each show, marking at any hour ===")


if __name__ == "__main__":
    unittest.main()
