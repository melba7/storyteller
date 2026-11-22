"""Tests for "Mark ads when the gathering is done.command": it starts nothing without a typed yes,
it waits while a gathering window has work running under it or a gathering tool runs on its own,
it does not wait for a gathering window that only waits for Return, and it starts the marking with
the yes already given. The gathering is played by small stand-in programs. No Mac needed.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WAIT = os.path.join(HERE, "Mark ads when the gathering is done.command")
MARK = os.path.join(HERE, "Mark ads in the teaching episodes.command")

# Stand-in for the marking: writes down whether the yes came with it and whether the gathering's
# work was over when it started.
STAND_IN_MARK = """#!/bin/bash
if [ -e "$WORK_DONE" ]; then when=after; else when=before; fi
echo "yes=$TEACH_YES started=$when" > "$STARTED"
"""

# Stand-in for a gathering window: works for a moment, then waits for Return as the real one does.
STAND_IN_GATHER = """#!/bin/bash
sleep 1.5 | cat
touch "$WORK_DONE"
read -r _
"""


@unittest.skipUnless(shutil.which("pgrep"), "pgrep is not installed")
class WaitTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.home)
        os.makedirs(self.bin)
        self.started = os.path.join(self.root, "started")
        self.work_done = os.path.join(self.root, "work-done")
        self.mark = self.program(os.path.join(self.root, "mark.command"), STAND_IN_MARK)
        # The Mac's caffeinate is not on this machine: a stand-in that does nothing.
        self.program(os.path.join(self.bin, "caffeinate"), "#!/bin/bash\nexit 0\n")
        self.env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TEACH_MARK": self.mark,
                    "TEACH_LOOK_SECONDS": "0.2", "STARTED": self.started, "WORK_DONE": self.work_done}

    def program(self, path, text):
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)
        return path

    def run_wait(self, typed):
        return subprocess.run(["bash", WAIT], env=self.env, input=typed, capture_output=True,
                              text=True, timeout=60)

    def background(self, command):
        """Starts a stand-in that keeps running, with a pipe as its keyboard, and stops it at the
        end of the test."""
        process = subprocess.Popen(command, env=self.env, stdin=subprocess.PIPE,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(process.stdin.close)
        self.addCleanup(process.wait)
        self.addCleanup(process.kill)
        return process

    def what_started(self):
        with open(self.started) as f:
            return f.read().strip()

    def test_without_a_typed_yes_nothing_starts(self):
        for typed in ("no\n", "\n", ""):
            done = self.run_wait(typed)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn("you did not type yes", done.stdout)
            self.assertFalse(os.path.exists(self.started))

    def test_with_no_gathering_the_marking_starts_with_the_yes_given(self):
        done = self.run_wait(" Yes \n")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.what_started(), "yes=1 started=before")

    def test_it_says_what_it_uses_before_it_asks(self):
        done = self.run_wait("no\n")
        self.assertIn("uses the Claude plan this Mac is signed in to", done.stdout)

    def test_it_waits_for_a_gathering_window_that_is_working_but_not_for_its_return_key(self):
        gather = self.program(os.path.join(self.root, "Gather episodes for teaching.command"),
                              STAND_IN_GATHER)
        window = self.background(["bash", gather])
        time.sleep(0.3)
        done = self.run_wait("yes\n")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.what_started(), "yes=1 started=after")
        self.assertIn("still working", done.stdout)
        # The stand-in window still waits for Return, as the real one does when it is done.
        self.assertIsNone(window.poll())

    def test_it_waits_for_a_gathering_tool_that_runs_on_its_own(self):
        tool = self.program(os.path.join(self.root, "teach_transcribe.py"),
                            "import os, time\ntime.sleep(1.5)\n"
                            "open(os.environ['WORK_DONE'], 'w').close()\n")
        self.background(["python3", tool])
        time.sleep(0.3)
        done = self.run_wait("yes\n")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.what_started(), "yes=1 started=after")

    def test_the_log_says_when_the_wait_began_and_ended(self):
        self.run_wait("yes\n")
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as f:
            log = f.read()
        self.assertIn("waiting for the gathering", log)
        self.assertIn("the gathering is done", log)

    def test_a_missing_marking_file_is_said_before_any_wait(self):
        self.env["TEACH_MARK"] = os.path.join(self.root, "not-there.command")
        done = self.run_wait("yes\n")
        self.assertEqual(done.returncode, 2)
        self.assertIn("is missing", done.stdout)


class YesTests(unittest.TestCase):
    """The marking file passes the yes on to teach_label.py only when it was given beforehand."""

    def run_mark(self, **more):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        calls = os.path.join(root, "calls")
        os.makedirs(os.path.join(root, "bin"))
        for name, text in (("python3", '#!/bin/bash\necho "$*" >> "$CALLS"\nexit 4\n'),
                           ("caffeinate", '#!/bin/bash\nshift\nexec "$@"\n')):
            path = os.path.join(root, "bin", name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, 0o755)
        env = {"HOME": root, "PATH": "%s:/usr/bin:/bin" % os.path.join(root, "bin"), "CALLS": calls}
        env.update(more)
        subprocess.run(["bash", MARK], env=env, capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
        with open(calls) as f:
            return f.read()

    def test_a_double_click_does_not_pass_a_yes(self):
        self.assertNotIn("--yes", self.run_mark())

    def test_a_yes_given_before_the_wait_is_passed_on(self):
        self.assertIn("teach_label.py", self.run_mark(TEACH_YES="1"))
        self.assertIn("--yes", self.run_mark(TEACH_YES="1"))


if __name__ == "__main__":
    unittest.main()
