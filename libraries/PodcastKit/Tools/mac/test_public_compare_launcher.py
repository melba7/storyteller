"""Tests for the launcher "Test the public marks": python3, swift and caffeinate are stand-ins that write
down how they were called, so nothing is built or trained.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Test the public marks.command"
STAND_INS = {
    "python3": '#!/bin/bash\necho "python3 $*" >> "$CALLS"\nexit "${STAND_IN_CODE:-0}"\n',
    "swift": '#!/bin/bash\necho "swift $*" >> "$CALLS"\n[ "$*" = "build -c release --show-bin-path" ] && echo /bin/path\nexit 0\n',
    "caffeinate": '#!/bin/bash\nshift\nexec "$@"\n',
}


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        self.calls = os.path.join(self.root, "calls.txt")
        for name, text in STAND_INS.items():
            path = os.path.join(self.bin, name)
            with open(path, "w") as handle:
                handle.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.base = os.path.join(self.home, "Storyteller Lofi")

    def folder(self, *parts):
        os.makedirs(os.path.join(self.base, *parts), exist_ok=True)

    def run_launcher(self, **extra):
        env = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin", "CALLS": self.calls}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(HERE, NAME)], input="\n", env=env,
                              capture_output=True, text=True, timeout=60)

    def public(self, marked=True):
        self.folder("PodcastTeachingSporc")
        with open(os.path.join(self.base, "PodcastTeachingSporc", "episodes.json"), "w") as handle:
            handle.write("{}")
        if marked:
            self.folder("PodcastTeachingSporc", "labels")

    def test_without_the_sample_it_says_what_to_do_first(self):
        result = self.run_launcher()
        self.assertIn("Fetch a sample of public transcripts", result.stdout)
        self.assertEqual(result.returncode, 2)

    def test_without_marks_it_says_to_mark_first(self):
        self.public(marked=False)
        result = self.run_launcher()
        self.assertIn("Mark the public transcripts", result.stdout)
        self.assertEqual(result.returncode, 2)

    def test_builds_the_tool_and_runs_the_comparison_with_snapped_labels_when_there_are_some(self):
        self.public()
        self.folder("PodcastTeaching", "labels-snapped")
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout)
        with open(self.calls) as handle:
            calls = handle.read()
        self.assertIn("swift build -c release --product podcast-teach", calls)
        self.assertIn("teach_public_compare.py", calls)
        self.assertIn("--labels labels-snapped", calls)
        self.assertIn("--fit-tool /bin/path/podcast-teach", calls)

    def test_without_snapped_labels_it_uses_the_plain_ones(self):
        self.public()
        self.run_launcher()
        with open(self.calls) as handle:
            self.assertIn("--labels labels ", handle.read() + " ")

    def test_a_failed_comparison_is_said(self):
        self.public()
        result = self.run_launcher(STAND_IN_CODE="2")
        self.assertIn("did not finish", result.stdout)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
