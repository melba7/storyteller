"""Tests for "Score the ad skipping.command": when the scorer fails it says the exit code and the last
lines it printed in plain words. The stand-in swift and podcast-teach programs of test_teach_shell.py
are used; no Mac needed.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import subprocess

import test_teach_shell as shell


class ScoreLauncherTests(shell.Setup):
    def run_launcher(self, code, say=True):
        body = 'echo "reading episode 3"; echo "the last thing said"' if say else ":"
        self.program("podcast-teach", "#!/bin/bash\n%s\nexit %d\n" % (body, code))
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "BIN": self.bin, "FAIL": "", "NOOP": "", "BUSY": "", "CODES": ""}
        return subprocess.run(["bash", os.path.join(shell.HERE, "Score the ad skipping.command")], env=env,
                              input="\n", capture_output=True, text=True, timeout=60)

    def test_a_kill_is_said_with_its_code_and_the_last_lines(self):
        done = self.run_launcher(137)
        self.assertEqual(done.returncode, 1)
        self.assertIn("It ended with exit code 137: it was killed (signal 9), often because the Mac ran out of memory",
                      done.stdout)
        self.assertIn("  the last thing said", done.stdout)
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_a_tool_that_printed_nothing_says_so(self):
        done = self.run_launcher(134, say=False)
        self.assertIn("exit code 134: it crashed (signal 6)", done.stdout)
        self.assertIn("It printed nothing before it ended.", done.stdout)

    def test_a_plain_failure_says_its_code(self):
        done = self.run_launcher(1)
        self.assertIn("It ended with exit code 1.", done.stdout)

    def test_it_worked_and_the_not_set_up_code_are_as_before(self):
        # The closing sentence is the prompt of `read -p`, which a pipe does not show.
        done = self.run_launcher(0)
        self.assertEqual(done.returncode, 0)
        self.assertNotIn("did not work", done.stdout)
        done = self.run_launcher(2)
        self.assertEqual(done.returncode, 2)
        self.assertNotIn("did not work", done.stdout)

    def test_the_code_is_in_the_log(self):
        self.run_launcher(137)
        self.assertIn("The scoring ended with exit code 137", self.log())
