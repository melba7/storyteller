"""Tests for the launcher "Count publisher transcripts in my shows": it runs the real
probe_transcripts.py on a temporary home whose followed shows have addresses that refuse at once, so
no network is used. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Count publisher transcripts in my shows.command"


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.bin)
        os.symlink(sys.executable, os.path.join(self.bin, "python3"))

    def run_launcher(self):
        env = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin"}
        return subprocess.run(["/bin/bash", os.path.join(HERE, NAME)], input="\n", env=env,
                              capture_output=True, text=True, timeout=60)

    def reports(self):
        return glob.glob(os.path.join(self.home, "Storyteller Lofi", "logs", "publisher-transcripts-*.txt"))

    def test_without_the_show_list_it_says_what_to_do(self):
        result = self.run_launcher()
        self.assertIn("Sync Apple Podcasts", result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.reports(), [])

    def test_writes_a_report_even_when_every_feed_fails(self):
        folder = os.path.join(self.home, "Storyteller Lofi", "LofiMusic", "Podcasts")
        os.makedirs(folder)
        shows = {"shows": [{"title": "Alpha", "feed": "http://127.0.0.1:1/feed"}]}
        with open(os.path.join(folder, "apple-podcasts.json"), "w", encoding="utf-8") as handle:
            json.dump(shows, handle)
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.reports()), 1)
        self.assertIn("Saved:", result.stdout)
        self.assertIn("No feed was read", result.stdout)


if __name__ == "__main__":
    unittest.main()
