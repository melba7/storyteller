"""Tests for the launcher "Free up space from the teaching audio": it shows what would be freed, asks
for a typed yes, and deletes only after it. It runs the real teach_free.py and teach_backup.py on a
temporary home, with a copy of the running Python as the Mac's python3. No Mac, no network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

import teach_store as store
from teach_testing import entry, transcript

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Free up space from the teaching audio.command"


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        os.symlink(sys.executable, os.path.join(self.bin, "python3"))
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        os.makedirs(os.path.join(self.folder, "audio"))
        os.makedirs(os.path.join(self.folder, "transcripts"))
        os.makedirs(os.path.join(self.folder, "labels"))

    def episode(self, number, learned, truth=True):
        item = entry(number, audio=True, bytes=50)
        with open(os.path.join(self.folder, item["file"]), "w") as f:
            f.write("x" * 50)
        if learned:
            with open(os.path.join(self.folder, "transcripts", item["id"] + ".txt"), "w") as f:
                f.write(transcript(5))
            with open(os.path.join(self.folder, "labels", item["id"] + ".json"), "w") as f:
                f.write("{}")
            os.makedirs(os.path.join(self.folder, "sound-bank"), exist_ok=True)
            with open(os.path.join(self.folder, "sound-bank", item["id"] + ".json"), "w") as f:
                f.write('{"version": 1, "episode": "%s", "stretches": []}' % item["id"])
            if truth:
                os.makedirs(os.path.join(self.folder, "copies"), exist_ok=True)
                with open(os.path.join(self.folder, "copies", item["id"] + ".truth.txt"), "w") as f:
                    f.write("12.0 30.0\n")
        return item

    def run_launcher(self, typed):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin}
        return subprocess.run(["bash", os.path.join(HERE, NAME)], env=env, input=typed,
                              capture_output=True, text=True, timeout=120)

    def audio(self):
        return os.listdir(os.path.join(self.folder, "audio"))

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as f:
            return f.read()


class FileTests(unittest.TestCase):
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


class AskingTests(LauncherTests):
    def test_it_shows_what_would_go_and_deletes_only_after_a_typed_yes(self):
        learned = self.episode(1, learned=True)
        waiting = self.episode(2, learned=False)
        store.save_manifest(self.folder, [learned, waiting])
        done = self.run_launcher("yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("1 episodes have audio that can go", done.stdout)
        self.assertEqual(self.audio(), [waiting["id"] + ".mp3"])
        self.assertIn("Done", done.stdout)
        self.assertIn("free up space: deleting", self.log())

    def test_anything_but_yes_deletes_nothing(self):
        learned = self.episode(1, learned=True)
        store.save_manifest(self.folder, [learned])
        for typed in ("\n", "", "no\n", "y\n", "ye s\n", "yes please\n"):
            done = self.run_launcher(typed)
            self.assertEqual(done.returncode, 0, (typed, done.stdout))
            self.assertEqual(self.audio(), [learned["id"] + ".mp3"], typed)
            self.assertIn("Nothing was deleted", done.stdout, typed)

    def test_episodes_waiting_for_a_second_download_go_only_when_all_is_typed(self):
        done_one = self.episode(1, learned=True)
        waiting = self.episode(2, learned=True, truth=False)
        store.save_manifest(self.folder, [done_one, waiting])
        done = self.run_launcher("yes\n")
        self.assertIn("gives up that comparison", done.stdout)
        self.assertEqual(self.audio(), [waiting["id"] + ".mp3"])
        done = self.run_launcher("all\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.audio(), [])

    def test_when_only_waiting_episodes_are_left_yes_deletes_nothing_and_all_does(self):
        waiting = self.episode(1, learned=True, truth=False)
        store.save_manifest(self.folder, [waiting])
        done = self.run_launcher("yes\n")
        self.assertIn("Nothing was deleted", done.stdout)
        self.assertEqual(self.audio(), [waiting["id"] + ".mp3"])
        self.run_launcher("all\n")
        self.assertEqual(self.audio(), [])

    def test_with_nothing_to_free_it_does_not_ask(self):
        store.save_manifest(self.folder, [self.episode(1, learned=False)])
        done = self.run_launcher("yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertNotIn("Type yes", done.stdout)
        self.assertIn("Nothing to do", done.stdout)

    def test_while_a_run_works_in_the_folder_it_says_to_wait(self):
        learned = self.episode(1, learned=True)
        store.save_manifest(self.folder, [learned])
        with store.run_lock(self.folder):
            done = self.run_launcher("yes\n")
        self.assertEqual(done.returncode, 3, done.stdout)
        self.assertIn("still working", done.stdout)
        self.assertEqual(self.audio(), [learned["id"] + ".mp3"])

    def test_it_makes_a_backup_before_it_deletes(self):
        learned = self.episode(1, learned=True)
        store.save_manifest(self.folder, [learned])
        self.run_launcher("yes\n")
        backups = os.path.join(self.home, "Storyteller Lofi", "PodcastTeachingBackups")
        self.assertEqual(len(os.listdir(backups)), 1)


if __name__ == "__main__":
    unittest.main()
