"""Tests for "Measure the sound at the edges.command": it runs with stand-in swift and podcast-teach
programs on a temporary PATH and home, to check what it builds, what it runs, what it says for each
exit code and that nothing runs when the teaching folder is missing. No Mac, no audio.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import subprocess
import unittest

from test_teach_shell import HERE, Setup

NAME = "Measure the sound at the edges.command"


class EdgesLauncherFileTests(unittest.TestCase):
    def test_it_parses_can_be_run_and_keeps_to_what_bash_3_2_has(self):
        path = os.path.join(HERE, NAME)
        done = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
        for banned in [r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"&>>?", r"\|&", r"\bcoproc\b"]:
            self.assertIsNone(re.search(banned, code), banned)

    def test_the_readme_lists_it(self):
        with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
            self.assertTrue(NAME in f.read())


class EdgesLauncherTests(Setup):
    def tool(self, code, line):
        self.program("podcast-teach", '#!/bin/bash\necho "podcast-teach $*" >> "$CALLS"\necho "%s"\nexit %d\n'
                     % (line, code))

    def folder(self):
        return os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")

    def run_launcher(self, **more):
        os.makedirs(self.folder(), exist_ok=True)
        return self.run_script(NAME, **more)

    def test_it_builds_the_tool_and_runs_edges_on_the_teaching_folder(self):
        self.tool(0, "Verdict: Go.")
        done = self.run_launcher()
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(
            [line for line in self.called() if " teach_store.py hold" not in line],
            ["swift build -c release --product podcast-teach", "swift build -c release --show-bin-path",
             "podcast-teach edges " + self.folder()])
        self.assertIn("Done. The numbers are above and in", done.stdout)
        self.assertIn("edges-report.json", done.stdout)

    def test_what_it_prints_is_added_to_the_log(self):
        self.tool(0, "Verdict: No go.")
        self.run_launcher()
        log = self.log()
        self.assertIn(" edges ===", log)
        self.assertIn("Verdict: No go.", log)

    def test_exit_2_points_at_what_the_tool_printed_and_names_the_causes(self):
        self.tool(2, "There is no labels-snapped folder")
        done = self.run_launcher()
        self.assertEqual(done.returncode, 2, done.stdout)
        self.assertIn("There is no labels-snapped folder", done.stdout)
        for words in ("what the tool printed above", "Teach the phone again", "Check ads with a second download"):
            self.assertIn(words, done.stdout)

    def test_exit_1_says_some_episodes_were_left_out_and_to_try_again(self):
        self.tool(1, "b: could not be read")
        done = self.run_launcher()
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("Double-click this again", done.stdout)

    def test_a_missing_teaching_folder_stops_it_before_anything_is_built(self):
        done = self.run_script(NAME)
        self.assertEqual(done.returncode, 2, done.stdout)
        self.assertIn("There is no teaching folder", done.stdout)
        self.assertEqual(self.called(), [])

    def test_a_build_that_fails_stops_it_without_running_the_tool(self):
        self.tool(0, "never")
        done = self.run_launcher(BUILD_FAILS="1")
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("The tool did not build", done.stdout)
        self.assertFalse([line for line in self.called() if line.startswith("podcast-teach")])

    def test_without_swift_it_says_so(self):
        os.remove(os.path.join(self.bin, "swift"))
        done = self.run_launcher()
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("swift is missing", done.stdout)


if __name__ == "__main__":
    unittest.main()
