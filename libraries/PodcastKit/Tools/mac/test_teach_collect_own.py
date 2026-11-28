"""Tests for teach_collect.py --own-gb (with --only-ahead): the hourly episode preparing limits only
the audio of its own episodes (ahead.json), not all the audio kept in the teaching folder, which may
hold far more from big runs. Fakes only: no network, no real audio.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import tempfile
import unittest

import teach_ahead_set as ahead
import teach_collect as collect
import teach_store as store
from teach_testing import entry

MB = 1_000_000


class OwnBase(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.said, self.downloads = [], []
        # 300 MB of other audio kept already, far over every limit used below.
        self.others = [entry(n, audio=True, bytes=100 * MB) for n in (1, 2, 3)]
        self.ahead = [entry(n, size=40 * MB) for n in (10, 11, 12, 13)]
        store.save_manifest(self.folder, self.others + self.ahead)
        ahead.add_ahead(self.folder, [{"id": e["id"], "feed": "https://f", "guid": "g", "title": "t",
                                       "picked": 1} for e in self.ahead])

    def download(self, address, path, **more):
        self.downloads.append(address)
        return {"bytes": 40 * MB, "sha256": "a" * 64, "host": "cdn.example"}

    def go(self, *extra):
        # No free disk is asked for unless a test asks, so the tests do not depend on this machine's disk.
        return collect.main(["--folder", self.folder, "--shows", os.path.join(self.folder, "none.json"),
                             "--keep-free-gb", "0"] + list(extra), download=self.download,
                            sleep=lambda s: None, say=self.said.append)

    def downloaded(self):
        return len(self.downloads)


class OwnTests(OwnBase):
    def test_the_ahead_episodes_are_downloaded_though_the_folder_is_far_over_the_limit(self):
        self.assertEqual(self.go("--only-ahead", "--own-gb", "1"), 0, self.said)
        self.assertEqual(self.downloaded(), 4)

    def test_they_stop_when_their_own_audio_would_pass_the_limit(self):
        # 40 MB each and a limit of 0.1 GB: two fit, the third would make 120 MB.
        self.assertEqual(self.go("--only-ahead", "--own-gb", "0.1"), collect.SIZE_LIMIT)
        self.assertEqual(self.downloaded(), 2)
        self.assertTrue(any("own audio" in line for line in self.said), self.said)

    def test_audio_the_ahead_episodes_already_have_counts_and_other_audio_does_not(self):
        manifest = store.load_manifest(self.folder)
        for item in manifest:
            if item["id"] == self.ahead[0]["id"]:
                item.update(file="audio/%s.mp3" % item["id"], bytes=40 * MB)
        store.save_manifest(self.folder, manifest)
        self.go("--only-ahead", "--own-gb", "0.1")
        self.assertEqual(self.downloaded(), 1)  # 40 MB kept + 40 MB new = 80; a third would be 120

    def test_the_free_disk_check_stays(self):
        self.assertEqual(self.go("--only-ahead", "--own-gb", "1", "--keep-free-gb", "100000000"), 0)
        self.assertEqual(self.downloaded(), 0)
        self.assertTrue(any("free disk space" in line for line in self.said), self.said)

    def test_own_gb_without_only_ahead_is_refused_with_one_plain_line_and_nothing_happens(self):
        self.assertEqual(self.go("--own-gb", "1"), 2)
        self.assertEqual(len(self.said), 1)
        self.assertIn("--own-gb", self.said[0])
        self.assertIn("--only-ahead", self.said[0])
        self.assertEqual(self.downloaded(), 0)

    def test_the_limit_must_be_a_number_above_zero(self):
        for bad in ("0", "-1", "x", "nan"):
            with self.assertRaises(SystemExit) as stop:
                self.go("--only-ahead", "--own-gb", bad)
            self.assertEqual(stop.exception.code, 2, bad)
        self.assertEqual(self.downloaded(), 0)


class UnchangedTests(OwnBase):
    def test_only_ahead_with_max_gb_still_counts_every_kept_file(self):
        self.assertEqual(self.go("--only-ahead", "--max-gb", "0.25"), collect.SIZE_LIMIT)
        self.assertEqual(self.downloaded(), 0)  # 300 MB is kept already, the limit is 250 MB
        self.assertTrue(any("size limit on all kept audio" in line for line in self.said), self.said)

    def test_only_ahead_with_a_roomy_max_gb_downloads_as_before(self):
        self.assertEqual(self.go("--only-ahead", "--max-gb", "1"), 0)
        self.assertEqual(self.downloaded(), 4)
