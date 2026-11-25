"""Tests for the launcher "Fetch a sample of public transcripts": it asks for a typed yes, makes its own
Python folder, installs, logs in and runs sporc_sample.py. The Mac's python3, pip and the Hugging Face
login are stand-in scripts, so nothing is installed or downloaded.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Fetch a sample of public transcripts.command"

PYTHON3 = """#!/bin/bash
# stand-in for the system python3: only `-m venv DIR` is used
[ "$1" = "-m" ] && [ "$2" = "venv" ] || exit 9
mkdir -p "$3/bin"
cp "$STAND_IN_PYTHON" "$3/bin/python"
cp "$STAND_IN_HF" "$3/bin/hf"
chmod +x "$3/bin/python" "$3/bin/hf"
"""

VENV_PYTHON = """#!/bin/bash
# stand-in for the folder's own python
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$*" in
  "-c import huggingface_hub, pyarrow") [ -e "$HERE/installed" ] ;;
  "-m pip install"*) touch "$HERE/installed" ;;
  "-c import sys; from huggingface_hub import get_token"*) [ -e "$HF_HOME/token" ] ;;
  *sporc_sample.py*) echo "args: $*"; mkdir -p "$3"; echo "SPoRC sample: stand-in" ;;
  *) exit 9 ;;
esac
"""

HF = """#!/bin/bash
[ "$1 $2" = "auth login" ] || exit 9
mkdir -p "$HF_HOME" && touch "$HF_HOME/token"
"""


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        self.make(os.path.join(self.bin, "python3"), PYTHON3)
        self.make(os.path.join(self.root, "venv-python"), VENV_PYTHON)
        self.make(os.path.join(self.root, "hf"), HF)
        self.base = os.path.join(self.home, "Storyteller Lofi")

    def make(self, path, text):
        with open(path, "w") as handle:
            handle.write(text)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def run_launcher(self, typed, **extra):
        env = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin",
               "STAND_IN_PYTHON": os.path.join(self.root, "venv-python"),
               "STAND_IN_HF": os.path.join(self.root, "hf")}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(HERE, NAME)], input=typed, env=env,
                              capture_output=True, text=True, timeout=60)

    def test_nothing_starts_without_a_typed_yes(self):
        result = self.run_launcher("no\n\n")
        self.assertIn("did not type yes", result.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.base, "venv-sporc")))

    def test_the_notice_names_the_terms_before_it_asks(self):
        result = self.run_launcher("no\n\n")
        self.assertIn("research and educational use only", result.stdout)
        self.assertIn("huggingface.co/datasets/blitt/SPoRC", result.stdout)

    def test_first_time_it_installs_logs_in_and_makes_the_sample(self):
        result = self.run_launcher("yes\n\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Installing huggingface_hub and pyarrow", result.stdout)
        self.assertIn("Not logged in to Hugging Face yet", result.stdout)
        self.assertTrue(os.path.exists(os.path.join(self.base, "hf-cache", "token")))
        self.assertIn("--count 200", result.stdout)
        self.assertTrue(os.path.isdir(os.path.join(self.base, "PodcastTeachingSporc")))
        self.assertIn("Saved:", result.stdout)

    def test_the_second_time_it_neither_installs_nor_asks_to_log_in(self):
        self.run_launcher("yes\n\n")
        result = self.run_launcher("yes\n\n")
        self.assertNotIn("Installing", result.stdout)
        self.assertNotIn("Not logged in", result.stdout)
        self.assertEqual(result.returncode, 0)

    def test_the_count_can_be_changed_and_a_bad_one_is_ignored(self):
        self.assertIn("--count 50", self.run_launcher("yes\n\n", TEACH_SPORC_COUNT="50").stdout)
        self.assertIn("--count 200", self.run_launcher("yes\n\n", TEACH_SPORC_COUNT="lots").stdout)


if __name__ == "__main__":
    unittest.main()
