"""Tests for ad-cues.json in teach_publish.py: it is published like the other files (JSON, version
1, at most 4.5 MB) into every folder and listed in teaching.json with its checksum, its absence is
quiet, and a file without the lists the phone needs (starts, returns, shows, common, usual) is not
published and the old copy stays. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import unittest

import teach_publish as publish
from test_teach_publish import Setup, read

CUES = {"version": 1, "writtenAt": 1700000000, "episodes": 30, "starts": ["this episode is"],
        "returns": ["and we are"], "shows": [{"feed": "https://f", "starts": ["a b c"], "returns": []}],
        "common": ["about"], "usual": ["often"]}


class CuesTests(Setup):
    def test_it_is_published_to_every_folder_and_listed_with_its_checksum(self):
        path = self.source("ad-cues.json", CUES)
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "ad-cues.json")), read(path))
            listed = json.loads(read(self.published(folder, "teaching.json")))["files"]
            self.assertEqual(listed["ad-cues.json"],
                             {"sha256": hashlib.sha256(read(path)).hexdigest(), "bytes": len(read(path))})

    def test_a_missing_file_is_skipped_quietly_and_not_listed(self):
        self.source("show-settings.json", {"version": 1, "shows": []})
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual([m for m in self.messages if "ad-cues.json" in m], [])
        self.assertNotIn("ad-cues.json", json.loads(read(self.published(self.one, "teaching.json")))["files"])

    def test_an_unchanged_file_is_left_alone(self):
        self.source("ad-cues.json", CUES)
        self.main(self.one)
        self.messages.clear()
        self.main(self.one)
        self.assertIn("ad-cues.json in %s: unchanged." % self.one, self.messages)

    def test_a_file_without_the_lists_is_not_published_and_says_why(self):
        for name in ("starts", "returns", "shows", "common", "usual"):
            self.messages.clear()
            self.source("ad-cues.json", dict(CUES, **{name: "x"}))
            self.assertEqual(self.main(self.one), 2, name)
            self.assertFalse(os.path.exists(self.published(self.one, "ad-cues.json")))
            self.assertTrue(any("ad-cues.json" in m and "list of %s" % name in m
                                for m in self.messages), self.messages)

    def test_a_refused_file_leaves_the_old_published_one(self):
        self.source("ad-cues.json", CUES)
        self.main(self.one)
        before = read(self.published(self.one, "ad-cues.json"))
        for raw in (b"[]", b"{nope", json.dumps(dict(CUES, version=2)).encode()):
            self.source("ad-cues.json", raw=raw)
            self.assertEqual(self.main(self.one), 2, raw)
            self.assertEqual(read(self.published(self.one, "ad-cues.json")), before)

    def test_a_file_over_the_limit_is_refused(self):
        self.source("ad-cues.json", CUES)
        self.assertEqual(self.main(self.one, limit=10), 2)

    def test_the_names_are_kept_apart_from_the_six_files(self):
        self.assertEqual(publish.CUES, ("ad-cues.json", "ad-cues.json"))
        self.assertEqual(publish.OPTIONAL, (publish.AHEAD, publish.CUES))
        self.assertNotIn("ad-cues.json", [target for _, target in publish.FILES])


if __name__ == "__main__":
    unittest.main()
